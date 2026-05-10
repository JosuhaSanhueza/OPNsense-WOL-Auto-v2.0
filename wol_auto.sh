#!/bin/sh
# ======================================================
#  Script WOL v2.1 (ordenado por IP ascendente)
#  corregido - lógica case
#  optimizado (solo DHCP static mappings)
#  Tener en cuenta tu Broadcast si es máscara 24 es "192.168.12.255"
#  si es 16 "192.168.255.255"
# ======================================================

# === CONFIGURACIÓN DE RED ===
BROADCAST="192.168.12.255"
SUBRED="192.168.12"
RANGO_INICIO=101
RANGO_FIN=146

# === CONFIGURACIÓN DE TELEGRAM ===
CONFIG_FILE="/conf/config.xml"
BOT_TOKEN="TU_BOT_TELEGRAM"
CHAT_ID_1="TU_CHAT_ID1"
CHAT_ID_2="TU_CHAT_ID2"

# === API DE FERIADO ===
FERIADO_API="https://date.nager.at/api/v3/PublicHolidays/$(date +%Y)/CL"

LOG_FILE="/tmp/log_encendido_$(date +%Y%m%d_%H%M).txt"
: > "$LOG_FILE"
exec > "$LOG_FILE" 2>&1

hoy=$(date +%Y-%m-%d)
hoy_legible=$(date +%d/%m/%Y)

echo "--- INICIO: $hoy_legible $(date +%H:%M:%S) ---"
echo "Rango activo: $SUBRED.$RANGO_INICIO - $SUBRED.$RANGO_FIN"

# === TELEGRAM ===
enviar_mensaje() {
    for chat_id in "$CHAT_ID_1" "$CHAT_ID_2"; do
        [ -n "$chat_id" ] && curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
            -d "chat_id=$chat_id" \
            -d "parse_mode=Markdown" \
            --data-urlencode "text=$1" >/dev/null 2>&1
    done
}

enviar_log() {
    if [ -s "$LOG_FILE" ]; then
        for chat_id in "$CHAT_ID_1" "$CHAT_ID_2"; do
            [ -n "$chat_id" ] && curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
                -F "chat_id=$chat_id" \
                -F "document=@$LOG_FILE" >/dev/null 2>&1
        done
    fi
}

# === VALIDACIÓN DE IP ===
es_ip_valida() {
    ip="$1"
    ultimo=$(echo "$ip" | awk -F. '{print $4}')

    case "$ip" in
        "$SUBRED".*)
            [ "$ultimo" -ge "$RANGO_INICIO" ] && [ "$ultimo" -le "$RANGO_FIN" ] && return 0
            ;;
    esac

    return 1
}

# === 1. FERIADO ===
echo "[1/4] Verificando feriado..."
es_feriado=$(curl -s "$FERIADO_API" | grep -c "\"date\":\"$hoy\"")

if [ "$es_feriado" -gt 0 ]; then
    echo "Feriado detectado"
    enviar_mensaje "🚫 *Hoy $hoy_legible es feriado.* No se encienden equipos."
    enviar_log
    rm -f "$LOG_FILE"
    exit 0
fi

# === 2. EXTRAER HOSTS DHCP ===
echo "[2/4] Extrayendo hosts desde Dnsmasq..."

TMP_RAW="/tmp/raw_hosts.txt"
TMP_LIST="/tmp/hosts_wol.txt"

awk '
/<hosts / {inblock=1; mac=""; ip=""}
/<\/hosts>/ {
    if (mac != "" && ip != "") {
        print mac " " ip
    }
    inblock=0
}
inblock && /<hwaddr>/ {
    gsub(/.*<hwaddr>|<\/hwaddr>.*/, "", $0)
    mac=$0
}
inblock && /<ip>/ {
    gsub(/.*<ip>|<\/ip>.*/, "", $0)
    ip=$0
}
' "$CONFIG_FILE" > "$TMP_RAW"

while read -r mac ip; do
    if es_ip_valida "$ip"; then
        echo "$mac $ip" >> "$TMP_LIST"
    fi
done < "$TMP_RAW"

sort -t . -k4,4n "$TMP_LIST" -o "$TMP_LIST"

if [ ! -s "$TMP_LIST" ]; then
    echo "ERROR: No se encontraron hosts válidos"
    enviar_mensaje "❌ *Error:* No hay hosts válidos en el rango configurado"
    enviar_log
    exit 1
fi

# === 3. WOL ===
echo "[3/4] Enviando WOL..."
enviar_mensaje "⚡ *SanfcoLautaro:* Iniciando secuencia de encendido $hoy_legible."

while read -r mac ip; do
    echo "WOL → $ip ($mac)"
    /usr/local/bin/wol -i "$BROADCAST" "$mac"
done < "$TMP_LIST"

echo "Esperando 60s..."
sleep 60

# === 4. VERIFICACIÓN ===
echo "[4/4] Verificando equipos..."

# Definición de salto de línea para shell
NL="
"
no_respondieron=""

while read -r mac ip; do
    echo -n "Ping $ip... "
    if ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
        echo "OK"
    else
        echo "FALLÓ"
        no_respondieron="${no_respondieron}${NL}❌ $ip"
    fi
done < "$TMP_LIST"

# === RESULTADO ===
if [ -z "$no_respondieron" ]; then
    enviar_mensaje "✅ Todos los equipos encendieron correctamente."
else
    # Se agrega el mensaje encabezado y la lista abajo
    enviar_mensaje "⚠️ *Atención:* Equipos que no responden:${no_respondieron}"
fi

echo "--- FIN ---"

enviar_log
rm -f "$TMP_RAW" "$TMP_LIST" "$LOG_FILE"
exit 0

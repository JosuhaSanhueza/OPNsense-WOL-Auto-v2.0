#!/bin/sh
# ======================================================
#  Script WOL v2.0 (corregido - lógica case)
#  optimizado (solo DHCP static mappings)
#  Tener en cuenta tu Broadcast si es máscara 24 es "192.168.12.255"
#  si es 16 "192.168.255.255"
# ======================================================

# === CONFIGURACIÓN ===
BROADCAST="192.168.12.255"
CONFIG_FILE="/conf/config.xml"
BOT_TOKEN="TU_TOKEN"
CHAT_ID_1="TU_CHAT_ID"
CHAT_ID_2="TU_CHAT_ID2"
FERIADO_API="https://date.nager.at/api/v3/PublicHolidays/$(date +%Y)/CL"

LOG_FILE="/tmp/log_encendido_$(date +%Y%m%d_%H%M).txt"
: > "$LOG_FILE"
exec > "$LOG_FILE" 2>&1

hoy=$(date +%Y-%m-%d)
hoy_legible=$(date +%d/%m/%Y)

echo "--- INICIO: $hoy_legible $(date +%H:%M:%S) ---"

# === TELEGRAM ===
enviar_mensaje() {
    for chat_id in "$CHAT_ID_1" "$CHAT_ID_2"; do
        [ -n "$chat_id" ] && curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
            -d "chat_id=$chat_id" \
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

# === VALIDACIÓN DE IP (RANGO LAB) ===
es_ip_valida() {
    ip=$1
    ultimo=$(echo "$ip" | awk -F. '{print $4}')

    case $ip in
        192.168.12.*)
            [ "$ultimo" -ge 101 ] && [ "$ultimo" -le 146 ] && return 0
            ;;
    esac

    return 1
}

# === 1. FERIADO ===
echo "[1/4] Verificando feriado..."
es_feriado=$(curl -s "$FERIADO_API" | grep -c "\"date\":\"$hoy\"")

if [ "$es_feriado" -gt 0 ]; then
    echo "Feriado detectado"
    enviar_mensaje "🚫 Hoy $hoy_legible es feriado. No se encienden equipos."
    enviar_log
    rm -f "$LOG_FILE"
    exit 0
fi

# === 2. EXTRAER HOSTS DHCP ===
echo "[2/4] Extrayendo hosts DHCP..."

TMP_RAW="/tmp/raw_hosts.txt"
TMP_LIST="/tmp/hosts_wol.txt"

awk '
/<staticmap>/ {inblock=1; mac=""; ip=""}
/<\/staticmap>/ {
    if (mac != "" && ip != "") {
        print mac " " ip
    }
    inblock=0
}
inblock && /<mac>/ {
    gsub(/.*<mac>|<\/mac>.*/, "", $0)
    mac=$0
}
inblock && /<ipaddr>/ {
    gsub(/.*<ipaddr>|<\/ipaddr>.*/, "", $0)
    ip=$0
}
' "$CONFIG_FILE" > "$TMP_RAW"

# Filtrar por rango válido
while read -r mac ip; do
    if es_ip_valida "$ip"; then
        echo "$mac $ip" >> "$TMP_LIST"
    fi
done < "$TMP_RAW"

if [ ! -s "$TMP_LIST" ]; then
    echo "ERROR: No se encontraron hosts válidos"
    enviar_mensaje "❌ Error: No hay hosts válidos en el rango configurado"
    enviar_log
    exit 1
fi

echo "Hosts válidos:"
cat "$TMP_LIST"

# === 3. WOL ===
echo "[3/4] Enviando WOL..."

enviar_mensaje "⚡ Iniciando encendido de equipos ($hoy_legible)"

while read -r mac ip; do
    echo "WOL → $ip ($mac)"
    /usr/local/bin/wol -i "$BROADCAST" "$mac"
    sleep 0.05
done < "$TMP_LIST"

echo "Esperando 60s..."
sleep 60

# === 4. VERIFICACIÓN ===
echo "[4/4] Verificando equipos..."

no_respondieron=""

while read -r mac ip; do
    echo -n "Ping $ip... "
    if ping -c 1 -t 2 "$ip" >/dev/null 2>&1; then
        echo "OK"
    else
        echo "FALLÓ"
        no_respondieron="$no_respondieron\n❌ $ip"
    fi
done < "$TMP_LIST"

# === RESULTADO ===
if [ -z "$no_respondieron" ]; then
    enviar_mensaje "✅ Todos los equipos encendieron correctamente."
else
    enviar_mensaje "⚠️ Equipos que NO responden:$no_respondieron"
fi

echo "--- FIN ---"

enviar_log
rm -f "$TMP_RAW" "$TMP_LIST" "$LOG_FILE"
exit 0

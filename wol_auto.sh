#!/bin/sh
# ======================================================
#  Script WOL optimizado (solo DHCP static mappings)
#  Tener en cuenta tu Broadcast si es máscara 24 es "192.168.12.255"
#  si es 16 "192.168.255.255"
# ======================================================

# === CONFIGURACIÓN ===
BROADCAST="192.168.12.255"
CONFIG_FILE="/conf/config.xml"
BOT_TOKEN="TU_TOKEN"
CHAT_ID_1="TU_CHAT_ID"
FERIADO_API="https://date.nager.at/api/v3/PublicHolidays/$(date +%Y)/CL"

LOG_FILE="/tmp/log_encendido_$(date +%Y%m%d_%H%M).txt"
: >"$LOG_FILE"
exec >"$LOG_FILE"2>&1

hoy=$(date +%Y-%m-%d)
hoy_legible=$(date +%d/%m/%Y)

echo"--- INICIO:$hoy_legible$(date +%H:%M:%S) ---"

# === TELEGRAM ===
enviar_mensaje() {
curl-s-X POST"https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
-d"chat_id=$CHAT_ID_1" \
--data-urlencode"text=$1" >/dev/null2>&1
}

enviar_log() {
    [-s"$LOG_FILE" ] &&curl-s-X POST"https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
-F"chat_id=$CHAT_ID_1" \
-F"document=@$LOG_FILE" >/dev/null2>&1
}

# === 1. FERIADO ===
echo"[1/4] Verificando feriado..."
es_feriado=$(curl -s"$FERIADO_API" | grep -c"\"date\":\"$hoy\"")

if ["$es_feriado"-gt0 ];then
echo"Feriado detectado"
    enviar_mensaje"🚫 Hoy$hoy_legible es feriado. No se encienden equipos."
    enviar_log
rm-f"$LOG_FILE"
exit0
fi

# === 2. EXTRAER DHCP STATIC MAPPINGS ===
echo"[2/4] Extrayendo hosts DHCP (101-146)..."

TMP_LIST="/tmp/hosts_wol.txt"

awk'
/<staticmap>/ {inblock=1; mac=""; ip=""}
/<\/staticmap>/ {
    if (ip ~ /^192\.168\.12\.(10[1-9]|1[1-3][0-9]|14[0-6])$/ && mac != "") {
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
'"$CONFIG_FILE" >"$TMP_LIST"

if [ !-s"$TMP_LIST" ];then
echo"ERROR: No se encontraron hosts válidos"
    enviar_mensaje"❌ Error: No hay hosts DHCP válidos (101-146)"
    enviar_log
exit1
fi

echo"Hosts detectados:"
cat"$TMP_LIST"

# === 3. WOL ===
echo"[3/4] Enviando WOL..."

while read-r mac ip;do
echo"WOL →$ip ($mac)"
    /usr/local/bin/wol-i"$BROADCAST""$mac"
sleep0.1
done <"$TMP_LIST"

echo"Esperando 60s..."
sleep60

# === 4. VERIFICACIÓN ===
echo"[4/4] Verificando equipos..."

no_respondieron=""

while read-r mac ip;do
echo-n"Ping$ip... "
ifping-c1-t2"$ip" >/dev/null2>&1;then
echo"OK"
else
echo"FALLÓ"
no_respondieron="$no_respondieron\n❌$ip"
fi
done <"$TMP_LIST"

# === RESULTADO ===
if [-z"$no_respondieron" ];then
    enviar_mensaje"✅ Todos los equipos encendieron correctamente."
else
    enviar_mensaje"⚠️ Equipos que NO responden:$no_respondieron"
fi

echo"--- FIN ---"

enviar_log
rm-f"$TMP_LIST""$LOG_FILE"
exit0

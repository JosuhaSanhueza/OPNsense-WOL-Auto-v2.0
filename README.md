# OPNsense WOL Auto v2.0

Automatización de encendido de equipos mediante Wake-on-LAN (WOL) en OPNsense, con validación de feriados en Chile y notificaciones vía Telegram.

## 🚀 Características

* Encendido automático por WOL
* Integración con DHCP Static Mappings
* Filtrado por rango de IP (192.168.12.101–146)
* Verificación de equipos mediante ping
* Notificaciones por Telegram (mensaje + log)
* Detección automática de feriados en Chile
* Integración con `configd` (actions)
* Compatible con cron de OPNsense

---

## 📂 Estructura

* `wol_auto.sh` → Script principal
* `actions_wolauto.conf` → Integración con OPNsense configd
* `cron_example.txt` → Ejemplo de tarea programada

---

## ⚙️ Requisitos

* OPNsense
* DHCP con Static Mappings configurado
* Wake-on-LAN habilitado en los equipos
* Acceso a internet (para API de feriados y Telegram)

---

## 🔧 Instalación

### 1. Copiar script

```bash
nano /usr/local/bin/wol_auto.sh
chmod +x /usr/local/bin/wol_auto.sh
```

---

### 2. Configurar variables

Editar dentro del script:

```bash
BROADCAST="192.168.255.255"
BOT_TOKEN="TU_TOKEN"
CHAT_ID_1="TU_CHAT_ID"
```

---

### 3. Crear acción en OPNsense

```bash
nano /usr/local/opnsense/service/conf/actions.d/actions_wolauto.conf
```

---

### 4. Reiniciar configd

```bash
service configd restart
```

---

### 5. Ejecutar manualmente

```bash
configctl wolauto start
```

---

### 6. Configurar cron

Ver archivo `cron_example.txt`

---

## 🧠 Cómo funciona

El script lee `/conf/config.xml` y extrae:

* MAC addresses
* IPs desde DHCP Static Mappings

Filtra automáticamente el rango:

```
192.168.12.101 - 192.168.12.146
```

---

## 🔐 Seguridad

* No usa credenciales en texto plano (excepto Telegram)
* No depende de archivos externos
* Ejecución controlada por OPNsense

---

## 📡 Notificaciones

* Inicio de proceso
* Resultado final
* Log completo como archivo adjunto

---

## ⚠️ Notas

* No funcionará si no existen static mappings en DHCP
* Requiere que WOL esté habilitado en BIOS/NIC

---

## 👨‍💻 Autor

Josuha Sanhueza

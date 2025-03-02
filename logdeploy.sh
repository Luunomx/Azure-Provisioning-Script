#!/bin/bash

# Färgkoder för bättre läsbarhet
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Spara loggfil
LOG_FILE="deploy.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Tidsstämplad loggningsfunktion
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

# Kontrollfunktion för kommandon
check_status() {
    if [ $? -eq 0 ]; then
        log "${GREEN}$1 lyckades${NC}"
    else
        log "${RED}$1 misslyckades${NC}"
        exit 1
    fi
}

# Konfigureringsvariabler
RESOURCE_GROUP="MVCAppRG"
VM_NAME="MVCAppVM"
LOCATION="northeurope"
APP_NAME="DemoApp"
APP_NAME_SERVICE="$APP_NAME.service"
APP_NAME_DLL="$APP_NAME.dll"
USERNAME="azureuser"
IMAGE="Ubuntu2204"
SIZE="Standard_B1s"
LM_DIRECTORY=$(pwd)
VM_DIRECTORY="/home/$USERNAME/webapp"

log "${GREEN}=== Startar deployment ==="

# Skapa resursgrupp
log "${YELLOW}Skapar resursgrupp...${NC}"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
check_status "Skapa resursgrupp"

# Skapa VM och hämta dess IP
log "${YELLOW}Skapar virtuell maskin...${NC}"
VM_INFO=$(az vm create --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --image "$IMAGE" --admin-username "$USERNAME" --generate-ssh-keys --size "$SIZE" 2>&1)
check_status "Skapa VM"

PUBLIC_IP=$(echo "$VM_INFO" | jq -r .publicIpAddress)
if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == "null" ]]; then
    log "${RED}Misslyckades att hämta VM:ens publika IP${NC}"
    exit 1
fi
log "${GREEN}VM skapad med IP: $PUBLIC_IP${NC}"

# Öppna port 5000
log "${YELLOW}Öppnar port 5000...${NC}"
az vm open-port --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --port 5000 --priority 890
check_status "Öppna port"

# Skapa lokal MVC-app
log "${YELLOW}Skapar MVC-app lokalt...${NC}"
cd "$LM_DIRECTORY"
dotnet new mvc -n "$APP_NAME"
check_status "Skapa MVC-app"

# Sätt rätt sökväg till appen
APP_PATH="$LM_DIRECTORY/$APP_NAME"
log "Använder sökväg: $APP_PATH"

# Uppdatera landningssidan
if [ -f "$APP_PATH/Views/Home/Index.cshtml" ]; then
    log "${YELLOW}Uppdaterar landningssidan...${NC}"
    sed -i 's/Welcome/Hugo/g' "$APP_PATH/Views/Home/Index.cshtml"
    check_status "Uppdatera landningssidan"
else
    log "${RED}Filen Index.cshtml hittades inte!${NC}"
    exit 1
fi

# Publicera appen
log "${YELLOW}Publicerar appen...${NC}"
cd "$APP_PATH"
dotnet publish -c Release
check_status "Publicera app"

# Vänta på att VM ska vara redo
log "${YELLOW}Väntar på att VM ska vara redo...${NC}"
for i in {1..6}; do
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$USERNAME@$PUBLIC_IP" "echo 'SSH fungerar'" && break
    log "Väntar ytterligare 10 sekunder..."
    sleep 10
done

# Konfigurera VM och skapa systemd-service
log "${YELLOW}Konfigurerar VM och skapar service...${NC}"
ssh "$USERNAME@$PUBLIC_IP" << EOF
    set -e
    mkdir -p $VM_DIRECTORY

    # Installera .NET
    wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    sudo dpkg -i packages-microsoft-prod.deb
    rm packages-microsoft-prod.deb
    sudo apt-get update
    sudo apt-get install -y aspnetcore-runtime-8.0 dotnet-sdk-9.0

    # Skapa systemd service fil
    sudo tee /etc/systemd/system/$APP_NAME_SERVICE << EOL
[Unit]
Description=$APP_NAME MVC Web Application
After=network.target

[Service]
WorkingDirectory=$VM_DIRECTORY
ExecStart=/usr/bin/dotnet $VM_DIRECTORY/$APP_NAME_DLL
Restart=always
User=azureuser
Group=azureuser
Environment=DOTNET_ENVIRONMENT=Production
Environment=ASPNETCORE_URLS=http://0.0.0.0:5000

[Install]
WantedBy=multi-user.target
EOL

    # Aktivera och starta servicen
    sudo systemctl daemon-reload
    sudo systemctl enable $APP_NAME_SERVICE
    sudo systemctl start $APP_NAME_SERVICE
EOF
check_status "Konfigurera VM och skapa service"

# Skapa katalog på VM
log "${YELLOW}Skapar katalog på VM...${NC}"
ssh "$USERNAME@$PUBLIC_IP" "mkdir -p $VM_DIRECTORY"

# Hitta den faktiska publiceringsmappen (hanterar olika .NET-versioner)
PUBLISH_DIR=$(find "$APP_PATH/bin/Release" -type d -name "publish" | head -n 1)

# Kontrollera att mappen hittades
if [ -z "$PUBLISH_DIR" ]; then
    log "${RED}Ingen publiceringsmapp hittades! Kontrollera att dotnet publish kördes korrekt.${NC}"
    exit 1
fi

# Kopiera filer från den hittade publiceringsmappen
log "${YELLOW}Kopierar filer till VM från: $PUBLISH_DIR ${NC}"
scp -r "$PUBLISH_DIR/"* "$USERNAME@$PUBLIC_IP:$VM_DIRECTORY"
check_status "Kopiera filer"


# Starta om tjänsten
log "${YELLOW}Startar om servicen...${NC}"
ssh "$USERNAME@$PUBLIC_IP" "sudo systemctl restart $APP_NAME_SERVICE"
check_status "Starta om service"

log "${GREEN}=== Deployment slutförd ===${NC}"
log "${BLUE}Appen är tillgänglig på: http://$PUBLIC_IP:5000${NC}"

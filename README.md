# Azure MVC App Deployment Script

## 📌 Beskrivning
Detta Bash-skript (`logdeploy.sh`) automatiserar provisionering av en Ubuntu-baserad virtuell maskin i Azure och distribuerar en ASP.NET Core MVC-applikation på den. Skriptet:

- Skapar en **resursgrupp** i Azure.
- Skapar en **Ubuntu 22.04-virtuell maskin**.
- Öppnar **port 5000** för att möjliggöra trafik till applikationen.
- Skapar och publicerar en lokal **ASP.NET Core MVC-app**.
- Distribuerar och konfigurerar applikationen på den virtuella maskinen.
- Skapar en **systemd-tjänst** för att köra applikationen automatiskt vid uppstart.

---

## 🔧 Förutsättningar
Innan du kör skriptet, se till att du har följande installerat:

- **Azure CLI** (`az`) – för att hantera resurser i Azure.
- **jq** – för att extrahera data från JSON-utdata.
- **.NET SDK 9.0** – för att skapa och publicera MVC-applikationen.
- **SSH & SCP** – för att kopiera filer och ansluta till den virtuella maskinen.

Om du inte har Azure CLI installerat, kan du installera det med Git Bash:

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

apt-get update
apt-get install -y wget
sudo apt remove --purge 'dotnet*'
sudo apt autoremove
sudo rm -rf /usr/share/dotnet
rm -rf ~/.dotnet
wget https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh
sudo bash dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet
sudo bash dotnet-install.sh --channel 7.0 --install-dir /usr/share/dotnet
rm dotnet-install.sh

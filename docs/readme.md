chmod +x *.sh

# Simulation
sudo ./ovs-installation.sh

# Application
sudo ./ovs-installation.sh --apply

# Remédiation avec la véritable MAC de Kali
sudo ./ovs-remediation.sh \
  --mac 08:00:27:AA:BB:10 \
  --apply

# Retour arrière
sudo ./ovs-rollback.sh --apply

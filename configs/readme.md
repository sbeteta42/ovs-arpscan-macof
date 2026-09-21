# Iniatialisation des scripts en mode eXecutable
chmod +x *.sh

# Simulation d'un dcript (exemple)
sudo ./ovs-installation.sh --apply

# Application (exemple)  
sudo ./ovs-installation.sh
 
# Remédiation avec la véritable MAC de Kali
sudo ./ovs-remediation.sh --mac 08:00:27:AA:BB:10 --apply

# Retour arrière
sudo ./ovs-rollback.sh --apply

## Sans --apply, les scripts affichent uniquement les opérations prévues.

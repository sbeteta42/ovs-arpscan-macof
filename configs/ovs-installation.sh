#!/usr/bin/env bash
# OVS-ARPSCAN-MACOF — création prudente du bridge de laboratoire.
# Configuration active jusqu'au prochain redémarrage. La persistance réseau
# doit être adaptée séparément à NetworkManager, systemd-networkd ou ifupdown.
# By ShadowHacker (sbeteta@beteta.org)

set -Eeuo pipefail
IFS=$'\n\t'

BRIDGE="${BRIDGE:-br0}"
MGMT_CIDR="${MGMT_CIDR:-192.168.1.2/24}"
LAB_INTERFACES=(ens33 ens34 ens35 ens36)
APPLY=0
ASSUME_YES=0

usage() {
  cat <<'EOF'
Usage: sudo ./ovs-installation.sh [options]

Options:
  --apply                 Appliquer réellement la configuration
  --yes                   Ne pas demander de confirmation
  --bridge NOM            Nom du bridge (défaut : br0)
  --address CIDR          IP de gestion (défaut : 192.168.1.2/24)
  --interfaces "LISTE"    Interfaces séparées par des espaces
  -h, --help              Afficher cette aide

Sans --apply, le script fonctionne en mode simulation.

Exemple :
  sudo ./ovs-installation.sh --apply --yes
EOF
}

die() { printf 'ERREUR : %s\n' "$*" >&2; exit 1; }
log() { printf '[OVS-LAB] %s\n' "$*"; }

run() {
  printf '+ '
  printf '%q ' "$@"
  printf '\n'
  (( APPLY == 1 )) && "$@"
}

while (( $# )); do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    --bridge) [[ $# -ge 2 ]] || die "Valeur manquante après --bridge"; BRIDGE="$2"; shift 2 ;;
    --address) [[ $# -ge 2 ]] || die "Valeur manquante après --address"; MGMT_CIDR="$2"; shift 2 ;;
    --interfaces)
      [[ $# -ge 2 ]] || die "Valeur manquante après --interfaces"
      read -r -a LAB_INTERFACES <<<"$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "Option inconnue : $1" ;;
  esac
done

(( EUID == 0 )) || die "Exécuter avec sudo ou en root."
[[ "$BRIDGE" =~ ^[a-zA-Z0-9_.:-]+$ ]] || die "Nom de bridge invalide."
[[ "$MGMT_CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || die "CIDR invalide."

for command_name in ip ovs-vsctl ovs-ofctl ovs-appctl systemctl; do
  command -v "$command_name" >/dev/null 2>&1 || die "Commande absente : $command_name"
done

for interface_name in "${LAB_INTERFACES[@]}"; do
  [[ -e "/sys/class/net/$interface_name" ]] || die "Interface introuvable : $interface_name"
done

log "Bridge : $BRIDGE"
log "Adresse de gestion : $MGMT_CIDR"
log "Ports : ${LAB_INTERFACES[*]}"
log "Vérifiez que ces interfaces sont réservées au laboratoire isolé."

if (( APPLY == 0 )); then
  log "MODE SIMULATION — aucune modification ne sera effectuée."
elif (( ASSUME_YES == 0 )); then
  read -r -p "Appliquer cette configuration OVS ? [oui/N] " answer
  [[ "$answer" == "oui" ]] || die "Opération annulée."
fi

run systemctl enable --now openvswitch-switch
run ovs-vsctl --may-exist add-br "$BRIDGE"

for interface_name in "${LAB_INTERFACES[@]}"; do
  run ip link set "$interface_name" up
  run ovs-vsctl --may-exist add-port "$BRIDGE" "$interface_name"
done

run ip link set "$BRIDGE" up
run ip addr replace "$MGMT_CIDR" dev "$BRIDGE"

if (( APPLY == 1 )); then
  log "Configuration appliquée. Contrôles :"
  ovs-vsctl show
  ip -br addr show "$BRIDGE"
  ovs-ofctl show "$BRIDGE"
  log "FreeSCO doit rester l'unique passerelle du LAN : 192.168.1.1."
else
  log "Relancez avec --apply après vérification des interfaces."
fi


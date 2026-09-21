#!/usr/bin/env bash
# OVS-ARPSCAN-MACOF — liste blanche de MAC sur un port OVS.
# Destiné au laboratoire isolé. Ne remplace ni DHCP Snooping ni DAI.
# By ShadowHacker (sbeteta@beteta.org)

set -Eeuo pipefail
IFS=$'\n\t'

BRIDGE="${BRIDGE:-br0}"
PORT_NAME="${PORT_NAME:-ens34}"
ALLOWED_MAC="${ALLOWED_MAC:-}"
COOKIE="0x4d41434f46"
STATE_DIR="${STATE_DIR:-/var/tmp/ovs-arpscan-macof}"
APPLY=0
ASSUME_YES=0

usage() {
  cat <<'EOF'
Usage: sudo ./ovs-remediation.sh --mac MAC [options]

Options:
  --mac MAC          MAC légitime du poste raccordé au port
  --port NOM         Port OVS à protéger (défaut : ens34)
  --bridge NOM       Bridge OVS (défaut : br0)
  --apply            Appliquer les règles
  --yes              Ne pas demander de confirmation
  -h, --help         Afficher cette aide

Sans --apply, le script affiche les contrôles et les commandes prévues.

Exemple :
  sudo ./ovs-remediation.sh --mac 08:00:27:aa:bb:10 --apply
EOF
}

die() { printf 'ERREUR : %s\n' "$*" >&2; exit 1; }
log() { printf '[OVS-REMEDIATION] %s\n' "$*"; }

run() {
  printf '+ '
  printf '%q ' "$@"
  printf '\n'
  (( APPLY == 1 )) && "$@"
}

while (( $# )); do
  case "$1" in
    --mac) [[ $# -ge 2 ]] || die "Valeur manquante après --mac"; ALLOWED_MAC="${2,,}"; shift 2 ;;
    --port) [[ $# -ge 2 ]] || die "Valeur manquante après --port"; PORT_NAME="$2"; shift 2 ;;
    --bridge) [[ $# -ge 2 ]] || die "Valeur manquante après --bridge"; BRIDGE="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Option inconnue : $1" ;;
  esac
done

(( EUID == 0 )) || die "Exécuter avec sudo ou en root."
for command_name in ovs-vsctl ovs-ofctl ovs-appctl awk date; do
  command -v "$command_name" >/dev/null 2>&1 || die "Commande absente : $command_name"
done

[[ -n "$ALLOWED_MAC" ]] || die "Utilisez --mac avec la MAC réellement relevée sur Kali."
[[ "$ALLOWED_MAC" =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ ]] || die "Adresse MAC invalide : $ALLOWED_MAC"
ovs-vsctl br-exists "$BRIDGE" || die "Bridge introuvable : $BRIDGE"
ovs-vsctl port-to-br "$PORT_NAME" 2>/dev/null | grep -Fxq "$BRIDGE" || die "$PORT_NAME n'appartient pas à $BRIDGE"

OFPORT=$(ovs-vsctl get Interface "$PORT_NAME" ofport | tr -d '"')
[[ "$OFPORT" =~ ^[1-9][0-9]*$ ]] || die "Numéro OpenFlow invalide pour $PORT_NAME : $OFPORT"

CONTROLLERS=$(ovs-vsctl get-controller "$BRIDGE" | tr -d '[]" ')
[[ -z "$CONTROLLERS" ]] || die "Un contrôleur OpenFlow est déclaré ($CONTROLLERS). Validez la politique avec son administrateur."

log "Bridge=$BRIDGE, port=$PORT_NAME, ofport=$OFPORT, MAC autorisée=$ALLOWED_MAC"
log "Effet : toute autre MAC source reçue sur ce port sera rejetée."

if (( APPLY == 0 )); then
  log "MODE SIMULATION — aucune règle ne sera modifiée."
elif (( ASSUME_YES == 0 )); then
  read -r -p "Appliquer la liste blanche sur $PORT_NAME ? [oui/N] " answer
  [[ "$answer" == "oui" ]] || die "Opération annulée."
fi

if (( APPLY == 1 )); then
  install -d -m 700 "$STATE_DIR"
  ovs-ofctl dump-flows "$BRIDGE" >"$STATE_DIR/flows-avant-remediation.txt"
  ovs-appctl fdb/show "$BRIDGE" >"$STATE_DIR/fdb-avant-remediation.txt"
  printf '%s\n' "$BRIDGE" >"$STATE_DIR/bridge"
  printf '%s\n' "$PORT_NAME" >"$STATE_DIR/port"
  printf '%s\n' "$ALLOWED_MAC" >"$STATE_DIR/mac-autorisee"
  date --iso-8601=seconds >"$STATE_DIR/date-application"
fi

# Suppression limitée aux anciennes règles créées par ce projet.
run ovs-ofctl del-flows "$BRIDGE" "cookie=$COOKIE/-1"
run ovs-ofctl add-flow "$BRIDGE" "cookie=$COOKIE,priority=0,actions=NORMAL"
run ovs-ofctl add-flow "$BRIDGE" "cookie=$COOKIE,priority=300,in_port=$OFPORT,dl_src=$ALLOWED_MAC,actions=NORMAL"
run ovs-ofctl add-flow "$BRIDGE" "cookie=$COOKIE,priority=200,in_port=$OFPORT,actions=drop"

if (( APPLY == 1 )); then
  log "Règles installées :"
  ovs-ofctl dump-flows "$BRIDGE" "cookie=$COOKIE/-1"
  log "Testez le ping légitime, puis la commande MACOF bornée à 500 trames."
  log "Retour arrière : sudo ./ovs-rollback.sh --apply"
else
  log "Relancez avec --apply lorsque les paramètres sont validés."
fi


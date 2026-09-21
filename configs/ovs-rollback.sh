#!/usr/bin/env bash
# OVS-ARPSCAN-MACOF — retrait des règles et restauration de l'état du TP.
# By ShadowHacker (sbeteta@beteta.org)

set -Eeuo pipefail
IFS=$'\n\t'

BRIDGE="${BRIDGE:-br0}"
COOKIE="0x4d41434f46"
STATE_DIR="${STATE_DIR:-/var/tmp/ovs-arpscan-macof}"
RESTORE_TABLE_SIZE=1
FLUSH_FDB=1
APPLY=0
ASSUME_YES=0

usage() {
  cat <<'EOF'
Usage: sudo ./ovs-rollback.sh [options]

Options:
  --bridge NOM          Bridge OVS (défaut : br0)
  --keep-table-size     Conserver mac-table-size
  --keep-fdb            Ne pas purger la table FDB
  --apply               Appliquer le retour arrière
  --yes                 Ne pas demander de confirmation
  -h, --help            Afficher cette aide

Le script retire seulement les règles portant le cookie du projet.
Il ne supprime ni le bridge, ni les ports, ni les règles d'autres outils.
EOF
}

die() { printf 'ERREUR : %s\n' "$*" >&2; exit 1; }
log() { printf '[OVS-ROLLBACK] %s\n' "$*"; }

run() {
  printf '+ '
  printf '%q ' "$@"
  printf '\n'
  (( APPLY == 1 )) && "$@"
}

while (( $# )); do
  case "$1" in
    --bridge) [[ $# -ge 2 ]] || die "Valeur manquante après --bridge"; BRIDGE="$2"; shift 2 ;;
    --keep-table-size) RESTORE_TABLE_SIZE=0; shift ;;
    --keep-fdb) FLUSH_FDB=0; shift ;;
    --apply) APPLY=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Option inconnue : $1" ;;
  esac
done

(( EUID == 0 )) || die "Exécuter avec sudo ou en root."
for command_name in ovs-vsctl ovs-ofctl ovs-appctl; do
  command -v "$command_name" >/dev/null 2>&1 || die "Commande absente : $command_name"
done
ovs-vsctl br-exists "$BRIDGE" || die "Bridge introuvable : $BRIDGE"

log "Le retour arrière cible uniquement le bridge $BRIDGE et le cookie $COOKIE."
if [[ -f "$STATE_DIR/flows-avant-remediation.txt" ]]; then
  log "Une sauvegarde informative est disponible dans $STATE_DIR."
fi

if (( APPLY == 0 )); then
  log "MODE SIMULATION — aucune modification ne sera effectuée."
elif (( ASSUME_YES == 0 )); then
  read -r -p "Retirer les règles du TP et nettoyer l'état transitoire ? [oui/N] " answer
  [[ "$answer" == "oui" ]] || die "Opération annulée."
fi

run ovs-ofctl del-flows "$BRIDGE" "cookie=$COOKIE/-1"

if (( RESTORE_TABLE_SIZE == 1 )); then
  run ovs-vsctl remove Bridge "$BRIDGE" other_config mac-table-size
fi

if (( FLUSH_FDB == 1 )); then
  run ovs-appctl fdb/flush "$BRIDGE"
fi

if (( APPLY == 1 )); then
  log "État après retour arrière :"
  ovs-ofctl dump-flows "$BRIDGE"
  ovs-vsctl get Bridge "$BRIDGE" other_config
  ovs-appctl fdb/show "$BRIDGE"
  log "Générez maintenant du trafic légitime entre Kali, Windows et FreeSCO."
  log "Vérifiez ensuite que leurs MAC réapparaissent sur les ports attendus."
else
  log "Relancez avec --apply pour exécuter le retour arrière."
fi


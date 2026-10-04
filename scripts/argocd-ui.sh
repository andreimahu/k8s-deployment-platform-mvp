#!/bin/sh
set -eu

action=$1
cluster=$2
kubeconfig=$3
port=$4
state_dir=$5
pid_file="$state_dir/$cluster-argocd-ui.pid"
log_file="$state_dir/$cluster-argocd-ui.log"
command_prefix="kubectl --kubeconfig $kubeconfig --context kind-$cluster -n argocd port-forward --address 127.0.0.1 svc/argocd-server "

# Check the command as well as the PID, since an old PID can be reused.
is_running() {
    [ -f "$pid_file" ] || return 1
    pid=$(cat "$pid_file")
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    args=$(ps -ww -p "$pid" -o args= 2>/dev/null) || return 1
    case "$args" in *"$command_prefix"*) return 0 ;; *) return 1 ;; esac
}

stop_forward() {
    if is_running; then
        if ! kill "$pid" 2>/dev/null && is_running; then
            printf 'Error: could not stop UI forwarding (PID %s).\n' "$pid" >&2
            return 1
        fi
        attempts=0
        while is_running && [ "$attempts" -lt 5 ]; do
            sleep 1
            attempts=$((attempts + 1))
        done
        if is_running; then
            printf 'Error: UI forward did not stop; PID file retained: %s\n' "$pid_file" >&2
            return 1
        fi
        printf 'Stopped Argo CD UI forwarding for %s.\n' "$cluster"
    fi
    rm -f -- "$pid_file"
}

case "$action" in
    stop)
        stop_forward
        exit 0
        ;;
    start) ;;
    *) printf 'Unknown action: %s\n' "$action" >&2; exit 1 ;;
esac

if is_running; then
    case "$args" in
        *"$command_prefix$port:443")
            printf 'Argo CD UI already forwarded: https://localhost:%s\n' "$port"
            exit 0
            ;;
    esac
    stop_forward
fi

umask 077
mkdir -p "$state_dir"
nohup kubectl --kubeconfig "$kubeconfig" --context "kind-$cluster" -n argocd \
    port-forward --address 127.0.0.1 svc/argocd-server "$port:443" \
    >"$log_file" 2>&1 </dev/null &
pid=$!
printf '%s\n' "$pid" >"$pid_file"

# Do not announce success until kubectl has bound the local port.
attempts=0
while [ "$attempts" -lt 30 ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
        cat "$log_file" >&2
        rm -f -- "$pid_file"
        printf 'Error: Argo CD UI forwarding failed.\n' >&2
        exit 1
    fi
    if grep -Fq "Forwarding from 127.0.0.1:$port ->" "$log_file"; then
        printf 'Argo CD UI: https://localhost:%s (background PID %s)\n' "$port" "$pid"
        printf 'Log: %s\nStop: make argocd-ui-stop CLUSTER_NAME=%s\n' "$log_file" "$cluster"
        exit 0
    fi
    sleep 1
    attempts=$((attempts + 1))
done

printf 'Error: timed out waiting for UI forwarding. Log: %s\n' "$log_file" >&2
cat "$log_file" >&2
stop_forward
exit 1

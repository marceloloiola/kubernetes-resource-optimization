#!/bin/bash
# check_slack.sh
# Calcula o SLACK: (Total CPU Requested) - (Total CPU Used)
# Requer: kubectl, jq, awk
printf "%-35s %-15s %-15s %-15s\n" "NAMESPACE" "REQUESTED" "USED" "SLACK (m)"
echo "---------------------------------------------------------------------------------------------------"

for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
    # 1. Soma REQUESTS (converte tudo para millicores usando jq)
    REQ=$(kubectl get pods -n "$ns" -o json 2>/dev/null | jq -r '
        [.items[].spec.containers[].resources.requests.cpu // "0"] | 
        map(
            if endswith("m") then 
                ltrimstr("0") | rtrimstr("m") | tonumber 
            else 
                tonumber * 1000 
            end
        ) | 
        add // 0
    ')

    # 2. Soma USED (Uso real atual)
    USE=$(kubectl top pods -n "$ns" --no-headers 2>/dev/null | awk '{
        cpu = $2
        if (cpu ~ /m$/) {
            sub(/m$/, "", cpu)
            sum += cpu
        } else if (cpu ~ /^[0-9.]+$/) {
            sum += cpu * 1000
        }
    }
    END { 
        if (sum == "") sum = 0
        print int(sum)
    }')

    # Defaults
    REQ=${REQ:-0}
    USE=${USE:-0}
    
    # Converte para inteiro
    REQ=$(printf "%.0f" "$REQ" 2>/dev/null || echo 0)
    USE=$(printf "%.0f" "$USE" 2>/dev/null || echo 0)
    
    SLACK=$((REQ - USE))

    # Exibe apenas se houver request configurado
    if [ "$REQ" -gt 0 ]; then
        printf "%-35s %-15s %-15s %-15s\n" "$ns" "${REQ}m" "${USE}m" "${SLACK}m"
    fi
done | sort -t'm' -k3 -rn

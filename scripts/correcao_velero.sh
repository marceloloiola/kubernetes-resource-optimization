#!/bin/bash
# correcao_velero.sh
# Script para otimizar recursos do namespace velero

echo "=========================================="
echo "OTIMIZAÇÃO: Namespace velero"
echo "=========================================="
echo ""

echo "Situação Atual:"
echo "  - node-agent (3x): 20m cada = 60m total"
echo "  - velero: 500m"
echo "  - TOTAL: 560m"
echo ""

echo "Após Otimização:"
echo "  - node-agent (3x): 5m cada = 15m total"
echo "  - velero: 30m"
echo "  - TOTAL: 45m"
echo "  - ECONOMIA: 515m (92%)"
echo ""

echo "=========================================="
echo "COMANDOS DE CORREÇÃO"
echo "=========================================="
echo ""

# 1. Identificar o tipo de workload
echo "1. Identificando workloads..."
echo ""

# Node-agent (provavelmente DaemonSet)
DAEMONSET=$(kubectl get daemonset -n velero -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$DAEMONSET" ]; then
    echo "✓ DaemonSet encontrado: $DAEMONSET"
    echo ""
    echo "Comando para corrigir node-agent (20m → 5m):"
    echo "---"
    echo "kubectl patch daemonset $DAEMONSET -n velero --type='json' -p='[{\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/resources/requests/cpu\", \"value\": \"5m\"}]'"
    echo ""
else
    echo "⚠ DaemonSet não encontrado automaticamente"
    echo "Execute manualmente:"
    echo "kubectl get daemonset -n velero"
    echo ""
fi

# Velero (Deployment)
DEPLOYMENT=$(kubectl get deployment -n velero -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$DEPLOYMENT" ]; then
    echo "✓ Deployment encontrado: $DEPLOYMENT"
    echo ""
    echo "Comando para corrigir velero (500m → 30m):"
    echo "---"
    echo "kubectl patch deployment $DEPLOYMENT -n velero --type='json' -p='[{\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/resources/requests/cpu\", \"value\": \"30m\"}]'"
    echo ""
else
    echo "⚠ Deployment não encontrado automaticamente"
    echo ""
fi

echo "=========================================="
echo "APLICAR CORREÇÕES?"
echo "=========================================="
echo ""
echo "Para aplicar as correções automaticamente, execute:"
echo ""
echo "  ./correcao_velero.sh apply"
echo ""
echo "Para apenas ver os comandos (modo dry-run):"
echo "  ./correcao_velero.sh"
echo ""

# Se receber argumento "apply", executa as correções
if [ "$1" == "apply" ]; then
    echo ""
    echo "APLICANDO CORREÇÕES..."
    echo ""
    
    if [ -n "$DAEMONSET" ]; then
        echo "Corrigindo DaemonSet $DAEMONSET..."
        kubectl patch daemonset "$DAEMONSET" -n velero --type='json' \
            -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "5m"}]'
        
        if [ $? -eq 0 ]; then
            echo "✓ DaemonSet atualizado com sucesso!"
        else
            echo "✗ Erro ao atualizar DaemonSet"
        fi
        echo ""
    fi
    
    if [ -n "$DEPLOYMENT" ]; then
        echo "Corrigindo Deployment $DEPLOYMENT..."
        kubectl patch deployment "$DEPLOYMENT" -n velero --type='json' \
            -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "30m"}]'
        
        if [ $? -eq 0 ]; then
            echo "✓ Deployment atualizado com sucesso!"
        else
            echo "✗ Erro ao atualizar Deployment"
        fi
        echo ""
    fi
    
    echo "=========================================="
    echo "VALIDAÇÃO"
    echo "=========================================="
    echo ""
    echo "Aguardando rollout..."
    sleep 5
    
    echo ""
    echo "Novos pods criados:"
    kubectl get pods -n velero
    echo ""
    
    echo "Novos requests configurados:"
    kubectl get pods -n velero -o custom-columns='NAME:.metadata.name,CPU_REQ:.spec.containers[*].resources.requests.cpu,MEM_REQ:.spec.containers[*].resources.requests.memory'
    echo ""
    
    echo "✅ CORREÇÃO CONCLUÍDA!"
    echo ""
    echo "Monitore o uso real nos próximos dias:"
    echo "  kubectl top pods -n velero"
    echo ""
fi

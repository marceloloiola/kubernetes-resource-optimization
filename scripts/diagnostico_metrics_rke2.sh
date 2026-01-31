#!/bin/bash
# diagnostico_metrics_rke2.sh
# Diagnóstico do metrics-server no RKE2

echo "=========================================="
echo "DIAGNÓSTICO: Metrics Server (RKE2)"
echo "=========================================="

# 1. Verificar se está instalado
echo "1. Verificando instalação do metrics-server..."
if kubectl get deployment rke2-metrics-server -n kube-system &>/dev/null; then
    echo "✓ rke2-metrics-server encontrado"
else
    echo "✗ rke2-metrics-server NÃO encontrado"
    echo "  Solução: Instale o metrics-server"
    exit 1
fi
echo ""

# 2. Verificar status do deployment
echo "2. Status do deployment rke2-metrics-server..."
kubectl get deployment rke2-metrics-server -n kube-system
echo ""

# 3. Verificar pods
echo "3. Verificando pods do rke2-metrics-server..."
kubectl get pods -n kube-system -l app.kubernetes.io/name=rke2-metrics-server
echo ""

# 4. Verificar logs
echo "4. Últimas linhas do log (possíveis erros)..."
METRICS_POD=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=rke2-metrics-server -o jsonpath='{.items[0].metadata.name}')
if [ -n "$METRICS_POD" ]; then
    echo "Pod: $METRICS_POD"
    kubectl logs -n kube-system "$METRICS_POD" --tail=20
else
    echo "✗ Pod do rke2-metrics-server não encontrado"
fi
echo ""

# 5. Testar API de métricas
echo "5. Testando API de métricas..."
echo "   Nodes:"
kubectl top nodes 2>&1 | head -5
echo ""
echo "   Pods (kube-system):"
kubectl top pods -n kube-system 2>&1 | head -5
echo ""

# 6. Verificar APIService
echo "6. Verificando APIService metrics.k8s.io..."
kubectl get apiservice v1beta1.metrics.k8s.io -o yaml | grep -A 10 "status:"
echo ""

# 7. Verificar se consegue coletar métricas
echo "7. Teste de coleta de métricas..."
if kubectl top nodes &>/dev/null; then
    echo "✓ Métricas de nodes: OK"
else
    echo "✗ Métricas de nodes: FALHA"
    echo "  Possíveis causas:"
    echo "  - APIService não está disponível"
    echo "  - Certificados inválidos"
    echo "  - Problema de conectividade com kubelet"
fi
echo ""

if kubectl top pods -n kube-system &>/dev/null; then
    echo "✓ Métricas de pods: OK"
else
    echo "✗ Métricas de pods: FALHA"
fi
echo ""

echo "=========================================="
echo "DIAGNÓSTICO COMPLETO"
echo "=========================================="
echo ""
echo "📋 Próximos passos:"
echo "  - Se tudo está OK, execute: ./check_slack_percent.sh"
echo "  - Para auditoria completa: ./check_slack_percent.sh > auditoria_\$(date +%Y%m%d).txt"

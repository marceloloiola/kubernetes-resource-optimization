# Case Detalhado: Otimização do Namespace Velero

## 📊 Resumo Executivo

**Namespace:** velero  
**Tipo:** Backup e Disaster Recovery  
**Resultado:** Redução de 92% no desperdício de CPU (560m → 45m)  
**Impacto:** Zero downtime, performance mantida, 515m de CPU liberados

---

## 🔍 Contexto

O Velero é uma ferramenta de backup e disaster recovery para Kubernetes. No cluster auditado, ele possuía:

- **3 pods de node-agent** (DaemonSet) - um por nó
- **1 pod velero** (Deployment) - controle central

### Situação Inicial

```
NAMESPACE   REQUESTED   USED    SLACK    WASTE %
velero      560m        6m      554m     98.9% 🔴
```

**Detalhamento por Pod:**

| Pod | Tipo | Request | Uso Real | Desperdício |
|-----|------|---------|----------|-------------|
| node-agent (3x) | DaemonSet | 20m cada | ~1m cada | 95% |
| velero | Deployment | 500m | ~5m | 99% |

---

## 🔎 Diagnóstico

### 1. Coleta de Dados Inicial

```bash
# Verificar requests configurados
kubectl get pods -n velero -o custom-columns='NAME:.metadata.name,CPU_REQ:.spec.containers[*].resources.requests.cpu,MEM_REQ:.spec.containers[*].resources.requests.memory'

# Output:
NAME                     CPU_REQ   MEM_REQ
node-agent-4mc7m         20m       128Mi
node-agent-bxpd4         20m       128Mi
node-agent-zfzx9         20m       128Mi
velero-b655f5996-jfsfv   500m      128Mi
```

### 2. Análise de Uso Real

```bash
# Verificar uso atual
kubectl top pods -n velero

# Output:
NAME                     CPU(cores)   MEMORY(bytes)
node-agent-4mc7m         1m           28Mi
node-agent-bxpd4         1m           27Mi
node-agent-zfzx9         1m           26Mi
velero-b655f5996-jfsfv   5m           245Mi
```

### 3. Validação com Prometheus/Grafana

Analisando 7 dias de histórico no Grafana:

**node-agent:**
- Uso médio: 0.0005 cpu (~0.5m)
- Uso de pico: 0.0007 cpu (~0.7m)
- Padrão: Extremamente estável, sem picos significativos

**velero:**
- Uso médio: 0.005 cpu (~5m)
- Uso de pico: 0.015 cpu (~15m)
- Padrão: Uso baixo e constante, com picos ocasionais (provavelmente durante execução de backups)

### 4. Análise de Workload

**node-agent:**
- Função: Coletar dados dos volumes persistentes em cada nó
- Carga: Leve, apenas monitora mudanças nos volumes
- Picos: Apenas durante snapshots (poucos segundos)

**velero:**
- Função: Controlador central, orquestra backups e restores
- Carga: Leve na maior parte do tempo, picos durante operações de backup
- Frequência de backups: Diária (cronjob)

---

## 🎯 Estratégia de Otimização

### Cálculo dos Novos Valores

**node-agent:**
```
Uso de pico: 0.7m
Margem de segurança: 7x
Request recomendado: 0.7m × 7 ≈ 5m ✅
```

**velero:**
```
Uso de pico: 15m
Margem de segurança: 2x
Request recomendado: 15m × 2 = 30m ✅
```

### Por que Estas Margens?

- **node-agent (7x)**: Margem alta pois são DaemonSets críticos e uso é extremamente previsível
- **velero (2x)**: Margem menor mas suficiente, considerando que picos são raros e curtos

---

## 🛠️ Implementação

### Script de Correção Criado

```bash
#!/bin/bash
# correcao_velero.sh

echo "🚀 Aplicando otimização no namespace velero..."

# 1. Corrigir DaemonSet node-agent (20m → 5m)
kubectl patch daemonset node-agent -n velero --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "5m"}]'

echo "✓ DaemonSet node-agent atualizado"

# 2. Corrigir Deployment velero (500m → 30m)
kubectl patch deployment velero -n velero --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "30m"}]'

echo "✓ Deployment velero atualizado"
echo ""
echo "Aguardando rollout..."
sleep 10

# 3. Validar novos valores
echo "📊 Novos valores configurados:"
kubectl get pods -n velero -o custom-columns='NAME:.metadata.name,CPU_REQ:.spec.containers[*].resources.requests.cpu'
```

### Execução

```bash
chmod +x correcao_velero.sh
./correcao_velero.sh
```

### Output da Execução

```
🚀 Aplicando otimização no namespace velero...
daemonset.apps/node-agent patched
✓ DaemonSet node-agent atualizado
deployment.apps/velero patched
✓ Deployment velero atualizado

Aguardando rollout...

📊 Novos valores configurados:
NAME                     CPU_REQ
node-agent-4xhcx         5m
node-agent-7lq5p         5m
node-agent-zhkv2         5m
velero-8766b5d9d-2rvcn   30m
```

---

## ✅ Validação

### 1. Verificação de Pods

```bash
# Pods recriados com sucesso
kubectl get pods -n velero

NAME                      READY   STATUS    RESTARTS   AGE
node-agent-4xhcx          1/1     Running   0          2m
node-agent-7lq5p          1/1     Running   0          2m
node-agent-zhkv2          1/1     Running   0          2m
velero-8766b5d9d-2rvcn    1/1     Running   0          1m
```

### 2. Confirmação de Valores

```bash
kubectl get pods -n velero -o custom-columns='NAME:.metadata.name,CPU_REQ:.spec.containers[*].resources.requests.cpu,MEM_REQ:.spec.containers[*].resources.requests.memory'

NAME                     CPU_REQ   MEM_REQ
node-agent-4xhcx         5m        128Mi     ✅ (antes: 20m)
node-agent-7lq5p         5m        128Mi     ✅ (antes: 20m)
node-agent-zhkv2         5m        128Mi     ✅ (antes: 20m)
velero-8766b5d9d-2rvcn   30m       128Mi     ✅ (antes: 500m)
```

### 3. Monitoramento Pós-Mudança

**Após 24 horas:**
```bash
kubectl top pods -n velero

NAME                     CPU(cores)   MEMORY(bytes)
node-agent-4xhcx         1m           29Mi    ✅ Estável
node-agent-7lq5p         1m           28Mi    ✅ Estável
node-agent-zhkv2         1m           27Mi    ✅ Estável
velero-8766b5d9d-2rvcn   6m           246Mi   ✅ Estável
```

### 4. Teste Funcional

```bash
# Executar backup manual para testar
velero backup create test-backup-pos-otimizacao

# Verificar se backup foi concluído com sucesso
velero backup describe test-backup-pos-otimizacao

# Output:
Phase: Completed ✅
Errors: 0
Warnings: 0
```

### 5. Verificação de Eventos

```bash
# Nenhum evento de erro relacionado a recursos
kubectl get events -n velero --sort-by='.lastTimestamp' | tail -20

# Sem OOMKilled ✅
# Sem CPU throttling ✅
# Sem Eviction ✅
```

---

## 📊 Resultados

### Antes vs Depois

| Métrica | Antes | Depois | Melhoria |
|---------|-------|--------|----------|
| **CPU Total Requested** | 560m | 45m | **-92%** |
| **CPU Total Used** | ~6m | ~6m | 0% |
| **Desperdício (Slack)** | 554m | 39m | **-93%** |
| **Desperdício (%)** | 98.9% | 86.7% | **-12.2pp** |
| **Margem de Segurança** | 93x | 7.5x | Mais saudável |
| **Downtime** | - | 0 seg | ✅ |
| **Problemas** | - | 0 | ✅ |

### Impacto no Cluster

**Recursos Liberados:**
- 515 millicores de CPU
- Equivalente a ~51% de uma CPU completa
- Permite executar dezenas de pods adicionais

**Distribuição do Ganho:**
```
Total liberado: 515m
├── node-agent (3x): 45m (15m × 3)
└── velero: 470m
```

### ROI (Return on Investment)

**Se o cluster fosse cloud:**
- Economia estimada: ~$20-30/mês (apenas CPU)
- Payback do esforço: < 1 dia
- ROI anual: ~$240-360

---

## 💡 Lições Aprendidas

### O que Funcionou Bem

1. **Análise de Histórico:** 7 dias de métricas deram confiança para definir valores
2. **Abordagem Gradual:** Começar pelo namespace menos crítico reduziu riscos
3. **Automação:** Script reutilizável facilita aplicação em outros namespaces
4. **Margem de Segurança:** Manter requests 5-7x o uso real evitou problemas

### Insights Técnicos

1. **DaemonSets são previsíveis:** Uso extremamente estável, margem alta é segura
2. **Backups são esporádicos:** Picos curtos não justificam requests altos
3. **Default é genérico:** Valores padrão são sempre superestimados

### Próximas Otimizações

Namespaces similares identificados:
- **istio-system** (98.5% desperdício) - Service mesh
- **longhorn-system** (82.4% desperdício) - Storage
- **cattle-monitoring-system** (88.3% desperdício) - Observabilidade

---

## 🔄 Processo de Reversão

Caso necessário reverter:

```bash
# Reverter DaemonSet
kubectl rollout undo daemonset/node-agent -n velero

# Reverter Deployment
kubectl rollout undo deployment/velero -n velero

# Ou aplicar valores originais manualmente
kubectl patch daemonset node-agent -n velero --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "20m"}]'

kubectl patch deployment velero -n velero --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "500m"}]'
```

**Observação:** Reversão não foi necessária. Mudanças foram bem-sucedidas.

---

## 📚 Referências

- [Velero Documentation](https://velero.io/docs/)
- [Kubernetes Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [DaemonSet Best Practices](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)

---

## 🎓 Competências Demonstradas

- ✅ Análise de métricas e observabilidade
- ✅ Kubernetes resource management avançado
- ✅ Scripting e automação
- ✅ Risk management e rollback planning
- ✅ Testing e validação
- ✅ Documentação técnica

---

**Autor:** Marcelo Loiola  
**Data:** Janeiro 2026  
**Status:** ✅ Implementado e Validado

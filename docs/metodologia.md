# Metodologia SRE: Resource Optimization

## Visão Geral

Este documento descreve a metodologia Site Reliability Engineering (SRE) aplicada para otimização de recursos em clusters Kubernetes, com foco em **Right-Sizing** de CPU e Memória.

A abordagem é **data-driven**, **iterativa** e **orientada a riscos**, seguindo as melhores práticas do Google SRE.

---

## Princípios Fundamentais

### 1. Observabilidade Primeiro

> "You can't improve what you don't measure" - Peter Drucker

**Requisitos:**
- ✅ Metrics-server funcional
- ✅ Prometheus/Grafana (opcional mas recomendado)
- ✅ Histórico mínimo de 7 dias
- ✅ Alertas configurados

### 2. Data-Driven Decisions

Todas as decisões devem ser baseadas em:
- Uso real medido (não estimativas)
- Tendências históricas (não momentos isolados)
- Análise de percentis (P95, P99)
- Correlação com eventos de negócio

### 3. Iteração Gradual

```
Piloto → Validação → Escala → Automação
```

Nunca otimize tudo de uma vez. Comece pequeno, valide, aprenda, escale.

### 4. Margem de Segurança

```
Request = Uso_de_Pico × Margem_de_Segurança
```

**Margens recomendadas:**
- Aplicações críticas: 1.5-2.0x
- Aplicações estáveis: 1.3-1.5x
- DaemonSets previsíveis: até 7x
- Jobs/CronJobs: 1.2-1.5x

---

## O Ciclo de Otimização

### Fase 1: DISCOVERY (Descoberta)

**Objetivo:** Identificar onde está o desperdício

**Ferramentas:**
- Scripts de auditoria automatizados
- Dashboards de observabilidade
- Análise de trends

**Entregável:**
```
Ranking de namespaces por:
1. Slack absoluto (millicores desperdiçados)
2. Percentual de desperdício
3. Impacto no cluster (%)
```

**Exemplo de Output:**
```
NAMESPACE          REQUESTED   USED    SLACK    WASTE%   PRIORITY
velero             560m        6m      554m     98.9%    🔴 ALTA
istio-system       1410m       21m     1389m    98.5%    🔴 ALTA
monitoring         950m        111m    839m     88.3%    🟡 MÉDIA
kube-system        3925m       625m    3300m    84.1%    🟡 MÉDIA
```

---

### Fase 2: ANALYSIS (Análise)

**Objetivo:** Entender o comportamento de cada workload

**Checklist de Análise:**

```bash
# 1. Identificar tipo de workload
kubectl get all -n <namespace>
→ Deployment, StatefulSet, DaemonSet?

# 2. Listar requests atuais
kubectl get pods -n <namespace> -o custom-columns='...'
→ Quanto cada pod pede?

# 3. Verificar uso real
kubectl top pods -n <namespace>
→ Quanto cada pod usa?

# 4. Análise de containers individuais
kubectl get pod <nome> -n <namespace> -o jsonpath='...'
→ App vs Sidecar?

# 5. Histórico no Prometheus
→ Últimos 7-30 dias
→ P50, P95, P99
→ Picos correlacionados com eventos?

# 6. Função do workload
→ O que essa aplicação faz?
→ Quando ela trabalha mais?
→ É crítica para o negócio?
```

**Matriz de Criticidade:**

| Tipo | Criticidade | Abordagem |
|------|-------------|-----------|
| **Infraestrutura crítica** (kube-system, istio) | ALTA | Conservador, margem 2x |
| **Aplicações de negócio** (prod) | ALTA | Conservador, margem 1.5-2x |
| **Ferramentas auxiliares** (velero, monitoring) | MÉDIA | Moderado, margem 1.3-1.5x |
| **Ambientes não-prod** (dev, hml) | BAIXA | Agressivo, margem 1.2x |

---

### Fase 3: PLANNING (Planejamento)

**Objetivo:** Definir valores seguros e estratégia de implementação

**Template de Planejamento:**

```yaml
Namespace: velero
Criticidade: MÉDIA
Data da Análise: 2026-01-31

Workload 1:
  Nome: node-agent
  Tipo: DaemonSet
  Pods: 3
  Request Atual: 20m por pod
  Uso Médio: 0.5m
  Uso P95: 0.7m
  Uso Pico: 1m
  Request Proposto: 5m
  Justificativa: Uso extremamente estável, margem de 7x é segura
  Risco: BAIXO

Workload 2:
  Nome: velero
  Tipo: Deployment
  Pods: 1
  Request Atual: 500m
  Uso Médio: 5m
  Uso P95: 12m
  Uso Pico: 15m
  Request Proposto: 30m
  Justificativa: Picos durante backups (curtos), margem de 2x
  Risco: BAIXO

Economia Total: 515m (92%)
Rollback Plan: kubectl rollout undo
Validação: Monitorar 24h, testar backup manual
```

---

### Fase 4: IMPLEMENTATION (Implementação)

**Objetivo:** Aplicar mudanças de forma segura e reversível

**Processo:**

1. **Criar script de correção**
```bash
#!/bin/bash
# correcao_<namespace>.sh

# Dry-run primeiro
echo "=== DRY RUN ==="
echo "Comando que será executado:"
echo "kubectl patch ..."
echo ""
read -p "Continuar? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Aplicar mudanças
    kubectl patch ...
fi
```

2. **Executar em horário de baixo movimento**
   - Evitar horário comercial para prod
   - Dev/Hml pode ser a qualquer momento

3. **Aplicar uma mudança por vez**
   - DaemonSet primeiro
   - Aguardar pods estabilizarem
   - Depois Deployment
   - Aguardar estabilizar

4. **Monitorar ativamente**
```bash
# Terminal 1: Watch pods
watch -n 2 kubectl get pods -n <namespace>

# Terminal 2: Watch events
kubectl get events -n <namespace> --watch

# Terminal 3: Watch metrics
watch -n 5 kubectl top pods -n <namespace>
```

---

### Fase 5: VALIDATION (Validação)

**Objetivo:** Confirmar que mudanças não causaram problemas

**Checklist de Validação:**

```bash
# ✅ 1. Pods estão rodando?
kubectl get pods -n <namespace>
→ Todos em Running?
→ Nenhum CrashLoopBackOff?
→ Restarts normais?

# ✅ 2. Novos valores aplicados?
kubectl get pods -n <namespace> -o custom-columns='...'
→ Requests atualizados corretamente?

# ✅ 3. Sem eventos de erro?
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
→ Sem OOMKilled?
→ Sem Evicted?
→ Sem FailedScheduling?

# ✅ 4. Métricas estáveis?
kubectl top pods -n <namespace>
→ Uso dentro do esperado?
→ Sem throttling visível?

# ✅ 5. Funcionalidade OK?
# Executar testes específicos da aplicação
→ Velero: rodar backup manual
→ Istio: verificar traffic routing
→ App: health checks, smoke tests

# ✅ 6. Sem alertas disparados?
# Verificar Prometheus/Alertmanager
→ Nenhum alerta novo?
→ SLOs mantidos?
```

**Período de Validação:**
- Crítico: 7 dias
- Médio: 3 dias  
- Baixo: 24 horas

---

### Fase 6: MONITORING (Monitoramento)

**Objetivo:** Garantir que otimização se mantém saudável

**Métricas para Monitorar:**

```yaml
Métricas de CPU:
  - container_cpu_usage_seconds_total
  - container_cpu_cfs_throttled_seconds_total
  - kube_pod_container_resource_requests_cpu_cores
  
Métricas de Memória:
  - container_memory_usage_bytes
  - container_memory_working_set_bytes
  - kube_pod_container_resource_requests_memory_bytes
  
Métricas de QoS:
  - kube_pod_status_qos_class
  - kube_node_status_allocatable
```

**Alertas Recomendados:**

```yaml
# Alerta: CPU Throttling Alto
alert: HighCPUThrottling
expr: |
  rate(container_cpu_cfs_throttled_seconds_total[5m]) > 0.25
for: 10m
annotations:
  summary: "Pod {{ $labels.pod }} está com throttling alto"
  
# Alerta: Aproximando do Request
alert: CPUNearRequest
expr: |
  container_cpu_usage_seconds_total / 
  kube_pod_container_resource_requests_cpu_cores > 0.8
for: 30m
annotations:
  summary: "Pod {{ $labels.pod }} usando 80%+ do request"
```

---

## Ferramentas e Automação

### Scripts Essenciais

1. **check_slack_percent.sh** - Auditoria periódica
2. **diagnostico_metrics.sh** - Validar pré-requisitos
3. **correcao_<namespace>.sh** - Aplicar otimizações

### Automação Contínua

```bash
# Cron job para auditoria semanal
0 9 * * 1 /path/to/check_slack_percent.sh > /var/log/k8s-audit-$(date +\%Y\%m\%d).log

# Notificar se desperdício > 80%
0 9 * * 1 /path/to/check_slack_percent.sh | awk '$5 > 80' | mail -s "Alerta: Desperdício Alto" sre@empresa.com
```

### Integração com CI/CD

```yaml
# GitLab CI example
audit-resources:
  script:
    - ./check_slack_percent.sh
    - ./analyze_results.sh
  only:
    - schedules
  artifacts:
    reports:
      metrics: audit_report.json
```

---

## KPIs e Métricas de Sucesso

### Métricas de Eficiência

```
Eficiência do Cluster = (CPU_Usado / CPU_Solicitado) × 100

Ideal: 60-80%
Aceitável: 40-60%
Ruim: <40%
Perigoso: >90% (pode indicar under-provisioning)
```

### Métricas de Impacto

- **Recursos Liberados:** Millicores e MiB economizados
- **Percentual de Economia:** (Slack_Antes - Slack_Depois) / Slack_Antes
- **ROI Financeiro:** Economia × Custo por Recurso
- **Namespaces Otimizados:** Contagem

### Métricas de Qualidade

- **Incidentes Relacionados:** 0 é a meta
- **Downtime Causado:** 0 segundos
- **SLO Mantido:** 100%
- **Reversões Necessárias:** 0

---

## Gerenciamento de Riscos

### Classificação de Risco

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---------------|---------|-----------|
| **OOMKilled** | Baixa | Alto | Margem de segurança, monitoramento |
| **CPU Throttling** | Baixa | Médio | Requests generosos, validação |
| **Downtime** | Muito Baixa | Alto | Rolling update, rollback plan |
| **Degradação** | Baixa | Médio | Testes funcionais, período de validação |

### Plano de Rollback

**Cenário 1: Pod não inicia**
```bash
# Verificar eventos
kubectl describe pod <nome> -n <namespace>

# Se for request muito baixo, aumentar
kubectl patch deployment <nome> -n <namespace> --type='json' \
  -p='[{"op": "replace", "path": "...", "value": "50m"}]'
```

**Cenário 2: OOMKilled**
```bash
# Aumentar memory request/limit
kubectl patch deployment <nome> -n <namespace> --type='json' \
  -p='[
    {"op": "replace", "path": ".../requests/memory", "value": "256Mi"},
    {"op": "replace", "path": ".../limits/memory", "value": "512Mi"}
  ]'
```

**Cenário 3: Performance degradada**
```bash
# Reverter completamente
kubectl rollout undo deployment/<nome> -n <namespace>

# Ou aumentar requests gradualmente
# 30m → 50m → 100m até estabilizar
```

---

## 💡 Boas Práticas

### Do's ✅

- ✅ Sempre analise dados antes de agir
- ✅ Comece por namespaces não-críticos
- ✅ Mantenha margem de segurança adequada
- ✅ Documente todas as mudanças
- ✅ Monitore após cada mudança
- ✅ Automatize o processo
- ✅ Compartilhe conhecimento com o time

### Don'ts ❌

- ❌ Não confie apenas em uso médio
- ❌ Não otimize tudo de uma vez
- ❌ Não ignore picos de uso
- ❌ Não esqueça dos sidecars
- ❌ Não pule a fase de validação
- ❌ Não faça em horário de pico (prod)
- ❌ Não deixe de ter rollback plan

---

## Checklist do SRE

Antes de iniciar otimização:

```
[ ] Metrics-server funcionando
[ ] Acesso necessário (kubectl, cluster)
[ ] Histórico de métricas disponível (7+ dias)
[ ] Janela de manutenção definida (se necessário)
[ ] Time avisado sobre mudanças
[ ] Rollback plan documentado
[ ] Alertas configurados
```

Durante a otimização:

```
[ ] Script de correção testado (dry-run)
[ ] Monitoramento ativo em múltiplos terminais
[ ] Comunicação aberta com time
[ ] Log de todas as ações
```

Após otimização:

```
[ ] Validação completa executada
[ ] Documentação atualizada
[ ] Métricas de sucesso coletadas
[ ] Lições aprendidas registradas
[ ] Próximos alvos identificados
```

---

## Referências

- [Google SRE Book](https://sre.google/sre-book/table-of-contents/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [CNCF Cloud Native Glossary](https://glossary.cncf.io/)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)

---

## Contribuindo

Esta metodologia é viva e deve evoluir. Contribua com:

- Lições aprendidas de casos reais
- Novas ferramentas e automações
- Métricas e KPIs relevantes
- Estudos de caso detalhados

---

**Autor:** Marcelo Loiola  
**Versão:** 1.0  
**Data:** Janeiro 2026  
**Status:** ✅ Validado em Produção

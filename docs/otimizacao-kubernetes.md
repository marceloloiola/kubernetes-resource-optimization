# Playbook: Otimização de Recursos em Kubernetes (Right-Sizing)

Este documento descreve o processo de identificação, análise e correção de alocação excessiva de recursos (CPU/Memória) em clusters Kubernetes. O objetivo é reduzir o **Slack** (diferença entre o que foi reservado e o que é realmente usado).

**Versão atualizada e testada em ambiente RKE2/Rancher**

---

## 📋 Índice

1. [Diagnóstico: Identificando o Desperdício](#1-diagnóstico-identificando-o-desperdício-global)
2. [Investigação: Encontrando o Pod "Gordo"](#2-investigação-encontrando-o-pod-gordo)
3. [Correção: Aplicando o Right-Sizing](#3-correção-aplicando-o-right-sizing)
4. [Validação](#4-validação)
5. [Análise de Desperdício por Namespace](#5-análise-de-desperdício-por-namespace)
6. [Caso Real: Otimização do Velero](#6-caso-real-otimização-do-velero)
7. [Cheat Sheet](#7-cheat-sheet-comandos-rápidos)
8. [Boas Práticas](#8-boas-práticas)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Diagnóstico: Identificando o Desperdício (Global)

O primeiro passo é ter uma visão macro de quais **Namespaces** são os maiores ofensores. Para isso, utilizamos um script que compara a soma dos `requests` com a soma do uso real (`top`).

### Pré-requisito: Metrics Server

Antes de executar os scripts de auditoria, verifique se o metrics-server está funcionando:

```bash
# Para RKE2
./diagnostico_metrics_rke2.sh

# Teste rápido
kubectl top nodes
```

Se o comando `kubectl top nodes` funcionar, você está pronto para executar a auditoria!

### Script de Auditoria de Slack (CPU) com Percentual

O script `check_slack_percent.sh` é a ferramenta principal para identificar desperdício:

```bash
# Executar auditoria completa
chmod +x check_slack_percent.sh
./check_slack_percent.sh

# Ver apenas os top 10 desperdiçadores
./check_slack_percent.sh | head -12

# Salvar resultado em arquivo
./check_slack_percent.sh > auditoria_$(date +%Y%m%d).txt
```

### Interpretação dos Resultados

**Exemplo de Output Real:**

```
NAMESPACE                           REQUESTED       USED            SLACK (m)       WASTE %
---------------------------------------------------------------------------------------------------
kube-system                         3925m           625m            3300m           84.1%
istio-system                        1410m           21m             1389m           98.5%
longhorn-system                     1200m           211m            989m            82.4%
velero                              560m            6m              554m            98.9%
cattle-monitoring-system            950m            111m            839m            88.3%
```

**Critérios de Priorização:**

- 🔴 **CRÍTICO** (Waste > 95%): Ajuste imediato
- 🟡 **ALTO** (Waste 80-95%): Ajuste em 1 semana
- 🟢 **MODERADO** (Waste 60-80%): Monitorar e ajustar
- ✅ **SAUDÁVEL** (Waste < 60%): Manter

---

## 2. Investigação: Encontrando o Pod "Gordo"

Após identificar o namespace problemático, precisamos descobrir qual carga de trabalho (Workload) está superdimensionada.

### Listar Requests por Pod

```bash
kubectl get pods -n <NAMESPACE> -o custom-columns='NAME:.metadata.name,CPU_REQ:.spec.containers[*].resources.requests.cpu,MEM_REQ:.spec.containers[*].resources.requests.memory'
```

**Exemplo Real (Velero):**

```
NAME                     CPU_REQ   MEM_REQ
node-agent-4mc7m         20m       128Mi
node-agent-bxpd4         20m       128Mi
node-agent-zfzx9         20m       128Mi
velero-b655f5996-jfsfv   500m      128Mi
```

### Analisar Uso Real

```bash
kubectl top pods -n <NAMESPACE>
```

**Exemplo Real (Velero):**

```
NAME                     CPU(cores)   MEMORY(bytes)
node-agent-4mc7m         1m           28Mi
node-agent-bxpd4         1m           27Mi
node-agent-zfzx9         1m           26Mi
velero-b655f5996-jfsfv   5m           245Mi
```

### Analisar Containers Individuais (App vs. Sidecar)

Muitas vezes o "vilão" não é a aplicação, mas o sidecar (ex: `istio-proxy`). O comando abaixo detalha o request de cada container dentro do pod:

```bash
kubectl get pod <NOME_DO_POD> -n <NAMESPACE> -o jsonpath='{range .spec.containers[*]}{.name}{"\t"}{.resources.requests.cpu}{"\t"}{.resources.requests.memory}{"\n"}{end}'
```

**Exemplo de Output (Desperdício com Istio):**

```
minha-app      20m    256Mi  <-- Ótimo
istio-proxy    100m   128Mi  <-- Vilão (Default alto para ambiente não-prod)
```

### Verificar Uso Real vs Solicitado

```bash
# Ver uso atual detalhado
kubectl top pod <NOME_DO_POD> -n <NAMESPACE> --containers

# Ver requests e limits configurados
kubectl describe pod <NOME_DO_POD> -n <NAMESPACE> | grep -A 5 "Requests"
```

---

## 3. Correção: Aplicando o Right-Sizing

Para corrigir, podemos aplicar patches diretamente no cluster (solução imediata) ou ajustar os manifestos no Git (solução definitiva/GitOps).

### A. Reduzindo a Aplicação (Container Principal)

Se a aplicação pede muito (ex: 200m) e usa pouco, reduzimos o request.

**Método Seguro (Por Posição - Index 0):** Usa-se quando não temos certeza do nome do container.

```bash
# Para StatefulSet
kubectl patch sts <NOME_DO_STS> -n <NAMESPACE> --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "10m"}]'

# Para Deployment
kubectl patch deployment <NOME_DO_DEPLOY> -n <NAMESPACE> --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "10m"}]'

# Para DaemonSet
kubectl patch daemonset <NOME_DO_DS> -n <NAMESPACE> --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "10m"}]'
```

**Para Memória:**

```bash
kubectl patch deployment <NOME> -n <NAMESPACE> --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "128Mi"}]'
```

### B. Reduzindo o Sidecar (Istio)

Para ambientes de Dev/Homologação, o default de 100m do Istio é excessivo. Usamos uma **Annotation** para sobrescrever esse valor por Pod.

**Comando de Patch (Injection):**

```bash
# Para StatefulSet
kubectl patch sts <NOME_DO_STS> -n <NAMESPACE> --type='merge' \
  -p '{"spec": {"template": {"metadata": {"annotations": {"sidecar.istio.io/proxyCPU": "10m", "sidecar.istio.io/proxyMemory": "50Mi"}}}}}'

# Para Deployment
kubectl patch deployment <NOME_DO_DEPLOY> -n <NAMESPACE> --type='merge' \
  -p '{"spec": {"template": {"metadata": {"annotations": {"sidecar.istio.io/proxyCPU": "10m", "sidecar.istio.io/proxyMemory": "50Mi"}}}}}'
```

### C. Script Automatizado de Correção

Para facilitar, crie scripts específicos por namespace. Exemplo:

```bash
#!/bin/bash
# correcao_<namespace>.sh

# Identificar workloads
DEPLOYMENT=$(kubectl get deployment -n <namespace> -o jsonpath='{.items[0].metadata.name}')

# Aplicar correção
kubectl patch deployment $DEPLOYMENT -n <namespace> --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "30m"}]'

# Validar
echo "Aguardando rollout..."
kubectl rollout status deployment/$DEPLOYMENT -n <namespace>

echo "Novos valores:"
kubectl get pods -n <namespace> -o custom-columns='NAME:.metadata.name,CPU_REQ:.spec.containers[*].resources.requests.cpu'
```

---

## 4. Validação

Após a aplicação dos patches, os Pods reiniciarão. Valide se a alteração surtiu efeito:

### 1. Aguarde o status `Running`:

```bash
kubectl get pods -n <NAMESPACE> -w
```

### 2. Verifique os novos valores alocados:

```bash
kubectl get pods -n <NAMESPACE> -o custom-columns='NAME:.metadata.name,CPU_REQ:.spec.containers[*].resources.requests.cpu,MEM_REQ:.spec.containers[*].resources.requests.memory'
```

**Resultado Esperado (Exemplo Velero):**

```
NAME                     CPU_REQ   MEM_REQ
node-agent-4xhcx         5m        128Mi     ✅ (antes: 20m)
node-agent-7lq5p         5m        128Mi     ✅ (antes: 20m)
node-agent-zhkv2         5m        128Mi     ✅ (antes: 20m)
velero-8766b5d9d-2rvcn   30m       128Mi     ✅ (antes: 500m)
```

### 3. Monitore o uso real após a mudança:

```bash
kubectl top pods -n <NAMESPACE>
```

### 4. Execute novamente o script de auditoria:

```bash
./check_slack_percent.sh | grep <NAMESPACE>
```

**Comparação Antes/Depois (Exemplo Velero):**

```
ANTES:  velero    560m    6m    554m    98.9%
DEPOIS: velero    45m     6m    39m     86.7%
```

---

## 5. Análise de Desperdício por Namespace

### Identificando Namespaces com Maior Desperdício

Execute o script de auditoria e analise os resultados focando em:

1. **Alto Slack Absoluto**: Namespaces desperdiçando mais recursos em termos totais
2. **Alto Percentual de Desperdício**: `(SLACK / REQUESTED) * 100`

### Script Completo

O script `check_slack_percent.sh` já calcula ambas as métricas automaticamente.

```bash
./check_slack_percent.sh
```

### Critérios de Priorização

Priorize a otimização de namespaces que atendam a um ou mais critérios:

- **Slack > 1000m** (1 CPU completo desperdiçado)
- **Desperdício > 80%** do solicitado
- **Namespaces de desenvolvimento/homologação** (geralmente sobre-provisionados)
- **Namespaces críticos com overcommit** no node

### Exemplo de Priorização Real

Com base em auditoria real:

| Prioridade | Namespace | Slack | Waste % | Ação |
|------------|-----------|-------|---------|------|
| 1 | velero | 554m | 98.9% | ✅ Corrigido |
| 2 | istio-system | 1389m | 98.5% | 🔄 Próximo |
| 3 | cattle-monitoring-system | 839m | 88.3% | 🔄 Próximo |
| 4 | kube-system | 3300m | 84.1% | 🔄 Próximo |
| 5 | longhorn-system | 989m | 82.4% | 🔄 Próximo |

---

## 6. Caso Real: Otimização do Velero

### Situação Inicial

**Namespace:** velero  
**Desperdício:** 98.9% (554m de 560m solicitados)

**Pods Identificados:**
```
NAME                     CPU_REQ   USED
node-agent (3x)         20m       ~0.5m cada
velero                  500m      ~5m
```

### Análise com Grafana/Prometheus

Gráficos mostraram:
- **node-agent**: Uso consistente de 0.0005 cpu (~0.5m)
- **velero**: Uso médio de 0.005 cpu (~5m) com picos em 0.015 cpu (~15m)

### Correção Aplicada

**Script Criado: `correcao_velero.sh`**

```bash
#!/bin/bash
# Otimização Velero

echo "🚀 Aplicando otimização no namespace velero..."

# Corrigir DaemonSet node-agent (20m → 5m)
kubectl patch daemonset node-agent -n velero --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "5m"}]'

# Corrigir Deployment velero (500m → 30m)
kubectl patch deployment velero -n velero --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "30m"}]'

echo "✅ Correções aplicadas!"
```

**Execução:**

```bash
chmod +x correcao_velero.sh
./correcao_velero.sh
```

### Resultado

| Métrica | Antes | Depois | Economia |
|---------|-------|--------|----------|
| node-agent (3x) | 60m | 15m | 75% |
| velero | 500m | 30m | 94% |
| **TOTAL** | **560m** | **45m** | **92%** |

**Impacto no Cluster:**
- 515m de CPU liberados
- Redução de desperdício de 98.9% para 86.7%
- Sem impacto na performance (requests ainda 5x maiores que uso real)

---

## 7. Cheat Sheet (Comandos Rápidos)

| Ação | Comando |
|------|---------|
| Ver Top CPU (Node) | `kubectl top nodes` |
| Ver Top CPU (Pod) | `kubectl top pods -n <ns>` |
| Ver Top CPU (Pod específico) | `kubectl top pod <nome-pod> -n <ns>` |
| Ver Top com containers | `kubectl top pod <nome> -n <ns> --containers` |
| Listar Deployments | `kubectl get deploy -n <ns>` |
| Listar StatefulSets | `kubectl get sts -n <ns>` |
| Listar DaemonSets | `kubectl get ds -n <ns>` |
| Listar Rollouts | `kubectl get rollout -n <ns>` |
| Ver requests/limits | `kubectl get pods -n <ns> -o custom-columns='NAME:.metadata.name,CPU_REQ:.spec.containers[*].resources.requests.cpu,MEM_REQ:.spec.containers[*].resources.requests.memory'` |
| Verificar Logs (Erro) | `kubectl logs <pod> -c <container> --previous` |
| Ver eventos do namespace | `kubectl get events -n <ns> --sort-by='.lastTimestamp'` |
| Descrever pod | `kubectl describe pod <nome> -n <ns>` |
| Ver todos os recursos | `kubectl get all -n <ns>` |
| Verificar rollout status | `kubectl rollout status deployment/<nome> -n <ns>` |
| Reverter rollout | `kubectl rollout undo deployment/<nome> -n <ns>` |
| Ver histórico de rollout | `kubectl rollout history deployment/<nome> -n <ns>` |

---

## 8. Boas Práticas

### Definindo Requests Adequados

1. **Monitore o uso real** por pelo menos 1 semana antes de ajustar
2. **Use métricas de pico**, não apenas médias
3. **Adicione margem de segurança**: 20-50% acima do uso de pico
4. **Teste em ambientes não-produtivos** primeiro

**Fórmula Recomendada:**

```
Request Ideal = (Uso de Pico × 1.3) + Buffer de Burst
```

**Exemplo Real (Velero):**
- Uso médio: 5m
- Uso de pico: 15m
- Request recomendado: 15m × 1.5 = 22.5m → **30m** ✅

### Diferença entre Requests e Limits

- **Requests**: Recursos **garantidos** para o pod (afeta scheduling)
- **Limits**: Recursos **máximos** que o pod pode usar (afeta throttling)

**Recomendação por Tipo de Aplicação:**

| Tipo | Requests | Limits |
|------|----------|--------|
| **Aplicações estáveis** | Uso pico × 1.3 | Requests × 1.5 |
| **Aplicações com burst** | Uso médio × 1.5 | Requests × 3 |
| **Aplicações críticas** | Uso pico × 1.5 | Requests × 2 |
| **Jobs/CronJobs** | Uso histórico | Requests × 2 |

### Ambientes Dev/Hml vs Produção

**Desenvolvimento/Homologação:**
- Requests mais baixos (recursos limitados)
- Limits mais agressivos
- Tolerância a throttling maior

**Produção:**
- Requests generosos (garantir QoS)
- Limits com margem confortável
- Priorizar disponibilidade

### Monitoramento Contínuo

Execute o script de auditoria periodicamente:

```bash
# Criar cron job para executar semanalmente
crontab -e

# Adicionar linha:
0 9 * * 1 /path/to/check_slack_percent.sh > /var/log/k8s-slack-report-$(date +\%Y\%m\%d).log
```

### Documentação de Mudanças

Mantenha um log de todas as otimizações:

```bash
# Criar arquivo de log
echo "$(date) - velero: 560m → 45m (92% economia)" >> otimizacoes.log
```

---

## 9. Troubleshooting

### Pod não inicia após redução de recursos

**Sintomas:**
- Pod fica em `Pending`
- Pod entra em `CrashLoopBackOff`
- Eventos mostram `Insufficient cpu` ou `Insufficient memory`

**Diagnóstico:**

```bash
# Verificar eventos
kubectl describe pod <nome> -n <ns>

# Ver logs
kubectl logs <nome> -n <ns>

# Ver eventos do namespace
kubectl get events -n <ns> --sort-by='.lastTimestamp' | tail -20
```

**Solução:**

```bash
# Se necessário, reverter
kubectl rollout undo deployment/<nome> -n <ns>

# Ou aumentar gradualmente
kubectl patch deployment <nome> -n <ns> --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "50m"}]'
```

### OOMKilled (Out of Memory)

**Sintomas:**
- Pod morto com status `OOMKilled`
- Logs mostram `Killed` ou `signal 9`

**Diagnóstico:**

```bash
# Verificar histórico
kubectl describe pod <nome> -n <ns> | grep -A 5 "Last State"

# Ver uso de memória antes do kill
kubectl top pod <nome> -n <ns> --containers
```

**Solução:**

Se um pod for morto por falta de memória após ajuste:

```bash
# Aumentar gradualmente (exemplo: 128Mi → 256Mi → 512Mi)
kubectl patch deployment <nome> -n <ns> --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "256Mi"}]'

# Também aumentar o limit
kubectl patch deployment <nome> -n <ns> --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "512Mi"}]'
```

### CPU Throttling Excessivo

**Sintomas:**
- Aplicação lenta
- Latência aumentada
- Logs mostram timeouts

**Diagnóstico:**

```bash
# No Prometheus/Grafana, buscar por:
# container_cpu_cfs_throttled_seconds_total

# Ou via kubectl (metrics-server não mostra throttling)
kubectl describe pod <nome> -n <ns> | grep -i throttl
```

**Solução:**

```bash
# Aumentar requests E limits
kubectl patch deployment <nome> -n <ns> --type='json' \
  -p='[
    {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "100m"},
    {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "200m"}
  ]'
```

### Pods não distribuem uniformemente

**Sintomas:**
- Um node está cheio enquanto outros estão vazios
- Novos pods ficam `Pending`

**Diagnóstico:**

```bash
# Ver distribuição de pods por node
kubectl get pods -A -o wide | awk '{print $8}' | sort | uniq -c

# Ver recursos alocados por node
kubectl describe nodes | grep -A 5 "Allocated resources"
```

**Solução:**

```bash
# Usar Pod Anti-Affinity ou Topology Spread Constraints
# Ou instalar o Descheduler do Kubernetes
```

### Metrics Server não funciona

**Sintomas:**
- `kubectl top` retorna erro
- Scripts de auditoria mostram `USED = 0m`

**Diagnóstico:**

```bash
./diagnostico_metrics_rke2.sh
```

**Solução:**

Ver seção de troubleshooting do metrics-server no script de diagnóstico.

---

## 10. Próximos Passos

### Roadmap de Otimização

Baseado em auditoria real, sugerimos esta ordem:

1. ✅ **velero** (560m → 45m) - CONCLUÍDO
2. 🔄 **istio-system** (1410m → ~50m) - Em análise
3. 🔄 **cattle-monitoring-system** (950m → ~200m) - Em análise
4. 🔄 **kube-system** (3925m → ~800m) - Requer cuidado extra
5. 🔄 **longhorn-system** (1200m → ~300m) - Em análise

### Ferramentas Complementares

- **Vertical Pod Autoscaler (VPA)**: Recomendações automáticas
- **Goldilocks**: Dashboard para recomendações de resources
- **Kube-resource-report**: Relatórios de utilização
- **Prometheus + Grafana**: Monitoramento de longo prazo

### Integração com GitOps

Após validar as mudanças no cluster, atualize os manifestos:

```yaml
# deployment.yaml
spec:
  template:
    spec:
      containers:
      - name: app
        resources:
          requests:
            cpu: 30m      # ✅ Atualizado após auditoria
            memory: 128Mi
          limits:
            cpu: 100m
            memory: 256Mi
```

---

## 11. Referências

- [Kubernetes Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Istio Sidecar Resource Annotations](https://istio.io/latest/docs/reference/config/annotations/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Vertical Pod Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
- [RKE2 Documentation](https://docs.rke2.io/)
- [Rancher Documentation](https://rancher.com/docs/)

---

**Última atualização:** Janeiro 2026  
**Ambiente testado:** RKE2 + Rancher  
**Versão:** 2.0 (com casos reais e validação)

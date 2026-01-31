# Como Reduzi 92% do desperdício no Cluster Kubernetes

## O Problema:

Tudo começou quando um dev chegou até a mim e me perguntou: "Marcelo, nosso cluster AMP (ApplicaApplication Management Platform) tem espaço suficiente para subirmos dois ambientes: develop e homolog?"

Essa pergunta me fez refletir muito sobre utilização de recursos. Eu já sabia que tínhamos recursos disponíveis, mas... quanto de recurso exatamente temos? Qual o consumo efetivo de cada aplicação? Decidi então fazer algo que ainda não tinha sido feito antes: auditar de verdade o que estávamos usando versus o que estávamos reservando no cluster.

Utilizamos Prometheus, analisei os dados e métricas, rodei alguns scripts que desenvolvi e... descobri um baita de um problema.

Nosso cluster Kubernetes (RKE2, com 3 nodes) estava solicitando **13,5 CPUs** mas efetivamente utilizando apenas **1,5 CPUs**. A eficiência era de míseros **10%**. Ou seja, estávamos desperdiçando **quase 90% dos recursos**.

Mas então como chegamos nessa realidade? Configurações genéricas copiadas de exemplos, aquele famoso "vamos colocar 500m pra garantir", e ninguém nunca revisou depois. O resultado: Um grande desperdício.

Decidi criar em repositório para documentar todo o processo que segui para diagnosticar, analisar e otimizar o cluster - resultando em **economia significativa** sem causar **nenhum problema** nas aplicações.

---

## O quê eu queria Alcançar

Meu objetivo: otimizar os recursos do cluster sem causar nenhum problema. Isso significava:

- Reduzir o desperdício de CPU e Memória
- Melhorar a eficiência do scheduler do Kubernetes
- Liberar recursos para novas aplicações
- Fazer tudo isso mantendo o SLA e a performance das aplicações
- Zero downtime

Basicamente, queria usar os recursos de forma inteligente, não apenas simplesmente cortar.

---

## Resultados alcançados

### Situação do Cluster (Antes da Otimização)

| Métrica | Valor |
|---------|-------|
| **CPU Total Solicitada** | 13.535m (~13.5 CPUs) |
| **CPU Total Utilizada** | 1.535m (~1.5 CPUs) |
| **Desperdício Médio** | **88.6%** 🔴 |
| **Eficiência** | 11.4% |

### Primeiro Caso: Namespace Velero (Como piloto)

Decidi começar pelo Velero (nossa ferramenta de backup) porque:
1. Não era crítico para o negócio (backups rodavam de madrugada)
2. Mostrava o maior percentual de desperdício (98.9%)
3. Se desse algum problema, seria fácil reverter

Os números antes da otimização:

| Métrica | Antes | Depois | Melhoria |
|---------|-------|--------|----------|
| CPU Solicitada | 560m | 45m | **-92%** ✅ |
| CPU Utilizada | ~6m | ~6m | Sem impacto |
| Desperdício | 98.9% | 86.7% | **-12.2pp** |
| Pods Afetados | 4 | 4 | 0 downtime |

**Resultado:** Liberados **515 millicores** de CPU mantendo **margem de segurança de 7x** o uso real.

---

## Como de fato eu fiz (Metodologia)

### 1. Diagnóstico - Descobrindo onde estava o Problema

Primeiro, precisava de dados. Desenvolvi scripts que fazem uma auditoria automatizada do cluster:

```bash
#!/bin/bash
# Script de auditoria que calcula: (CPU Requested) - (CPU Used)
# Output: Ranking de namespaces por percentual de desperdício

for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
    # Calcula requests configurados
    REQ=$(kubectl get pods -n "$ns" -o json | jq -r '...')
    
    # Coleta uso real via metrics-server
    USE=$(kubectl top pods -n "$ns" --no-headers | awk '...')
    
    # Calcula slack e percentual
    SLACK=$((REQ - USE))
    PERCENT=$(awk "BEGIN {printf \"%.1f\", ($SLACK / $REQ) * 100}")
done
```

O script me retornou esta lista (ordenada do pior para o melhor):

```
NAMESPACE                    REQUESTED   USED    SLACK    WASTE %
velero                       560m        6m      554m     98.9%  🔴
istio-system                 1410m       21m     1389m    98.5%  🔴
cattle-monitoring-system     950m        111m    839m     88.3%  🟡
kube-system                  3925m       625m    3300m    84.1%  🟡
longhorn-system              1200m       211m    989m     82.4%  🟡
```

### 2. Análise Profunda - Entendendo o Porquê

Para cada namespace com alto desperdício, fui a fundo:

**a) Identificação dos workloads:**
```bash
kubectl get pods -n velero -o custom-columns='NAME:.metadata.name,CPU_REQ:.spec.containers[*].resources.requests.cpu'
```

**Output:**
```
NAME                     CPU_REQ
node-agent-xxx (3x)      20m cada
velero-xxx               500m
```

**b) Correlação com uso real:**
```bash
kubectl top pods -n velero
```

**Output:**
```
NAME                     CPU(cores)   
node-agent-xxx           1m          ← Pediu 20m, usa 1m (95% desperdício)
velero-xxx               5m          ← Pediu 500m, usa 5m (99% desperdício)
```

**c) Validação com métricas históricas (Prometheus/Grafana):**
- Análise de 7 dias de histórico
- Identificação de picos de uso
- Cálculo de P95/P99 para definir requests adequados

### 3. Implementação - Aplicando as mudanças com Segurança

Minha estratégia foi:
- Abordagem gradual (um namespace por vez, nunca tudo de uma vez)
- Testar primeiro no cluster AMP 
- Rolling updates para garantir zero downtime
- Manter margem de segurança: requests = uso_pico × 1.5-2.0

Os comandos que apliquei no Velero:

```bash
# DaemonSet node-agent: 20m → 5m (uso real: ~1m)
kubectl patch daemonset node-agent -n velero --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "5m"}]'

# Deployment velero: 500m → 30m (uso real: ~5m)
kubectl patch deployment velero -n velero --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "30m"}]'
```

### 4. Validação - Confirmando que Deu Certo

Depois de aplicar as mudanças, fiz uma validação bem detalhada:

**Verificação de rollout:**
```bash
kubectl rollout status deployment/velero -n velero
# deployment "velero" successfully rolled out ✅
```

**b) Confirmação de novos valores:**
```bash
kubectl get pods -n velero -o custom-columns='NAME:.metadata.name,CPU_REQ:.spec.containers[*].resources.requests.cpu'

# Output:
NAME                     CPU_REQ
node-agent-xxx           5m      ✅ (antes: 20m)
velero-xxx               30m     ✅ (antes: 500m)
```

**c) Monitoramento pós-mudança:**
- ✅ Pods rodando normalmente
- ✅ Sem OOMKilled ou CPU throttling
- ✅ Latência e performance sem alteração
- ✅ Backups continuam funcionando

---

## Ferramentas que Usei

- **Kubernetes:** RKE2 (Rancher Kubernetes Engine 2)
- **Orquestração:** Rancher
- **Metrics:** rke2-metrics-server
- **Monitoramento:** Prometheus + Grafana
- **Backup:** Velero
- **Service Mesh:** Istio
- **Storage:** Longhorn
- **Scripts:** Bash + jq + kubectl

---

## O Que Criei (Artefatos)

### Scripts de Auditoria

- **`check_slack_percent.sh`**: Calcula desperdício por namespace
- **`diagnostico_metrics_rke2.sh`**: Valida funcionamento do metrics-server
- **`correcao_<namespace>.sh`**: Scripts automatizados de correção

### 2. Documentação Técnica

- **`otimizacao-kubernetes.md`**: Documentação completo com mais de 70 páginas
  - Metodologia de diagnóstico
  - Comandos de correção
  - Casos reais com antes/depois
  - Troubleshooting
  - Boas práticas

### 3. Processos Estabelecidos

- ✅ Auditoria semanal automatizada (cron job)
- ✅ Checklist de validação pré/pós mudança
- ✅ Documentação de decisões técnicas
- ✅ Integração com GitOps

---

## O que aprendi durante o processo

### Coisas que funcionaram bem

1. **Abordagem Data-Driven**: Decisões baseadas em métricas reais (Prometheus) e não em "achismos"
2. **Iteração Gradual**: Começar com namespace menos crítico (velero) reduziu riscos
3. **Automação**: Scripts reutilizáveis aceleram análise de outros namespaces
4. **Margem de Segurança**: Manter requests 5-7x maiores que uso real evitou problemas

### Desafios que enfrentei

1. **Metrics-server RKE2**: Naming diferente (`rke2-metrics-server` vs `metrics-server`)
2. **Parsing de Dados**: Necessidade de tratar formatos mistos (millicores "m" vs cores inteiros)
3. **Sidecars Istio**: Descobrir que grande parte do desperdício vinha dos proxies

### Próximos Passos

| Namespace | Potencial de Economia | Status |
|-----------|----------------------|--------|
| velero | 515m | ✅ Concluído |
| istio-system | ~1350m | 🔄 Planejado |
| cattle-monitoring | ~750m | 🔄 Planejado |
| kube-system | ~2500m | 🔄 Em análise |
| longhorn-system | ~850m | 🔄 Planejado |


---

## Competências que apliquei (SRE)

### Habilidades Técnicas
- Observabilidade: Prometheus, Grafana, metrics-server
- Kubernetes Avançado: Resource management, scheduling, QoS
- Automação: Bash scripting, jq, kubectl
- Troubleshooting: Diagnóstico sistemático de problemas complexos

### Práticas SRE
- Capacity Planning: Análise de tendências e projeções
- Cost Optimization: Redução de desperdício sem impacto em SLA
- Toil Reduction: Automação de auditorias e correções
- Documentation: Playbooks, runbooks e conhecimento compartilhado

### Soft Skills
- Iniciativa: Identificação proativa de problema não mapeado
- Pensamento Analítico: Decomposição de problema complexo
- Comunicação Técnica: Documentação clara e objetiva
- Risk Management: Abordagem gradual e reversível

---

## Como você pode usar esse projeto

### O que você precisa

```bash
# Ferramentas necessárias
- kubectl configurado
- jq instalado
- Acesso admin ao cluster
- metrics-server funcional
```

### Passo a Passo para aplica no seu Cluster

1. **Clone este repositório**
```bash
git clone https://github.com/seu-usuario/k8s-resource-optimization
cd k8s-resource-optimization
```

2. **Execute diagnóstico**
```bash
chmod +x diagnostico_metrics_rke2.sh
./diagnostico_metrics_rke2.sh
```

3. **Execute auditoria**
```bash
chmod +x check_slack_percent.sh
./check_slack_percent.sh > auditoria_$(date +%Y%m%d).txt
```

4. **Analise resultados e priorize namespaces**

5. **Para cada namespace:**
   - Analise requests vs uso real
   - Consulte métricas históricas
   - Calcule novo request: `uso_pico × 1.5`
   - Aplique patch gradualmente
   - Valide e monitore

### Estrutura do Repositório

```
k8s-resource-optimization/
├── README.md                          # Este arquivo
├── docs/
│   ├── otimizacao-kubernetes.md      # Documentação completa
│   └── caso-velero.md                # Case detalhado
├── scripts/
│   ├── check_slack_percent.sh        # Auditoria principal
│   ├── diagnostico_metrics_rke2.sh   # Diagnóstico
│   └── correcao_velero.sh            # Exemplo de correção
└── exemplos/
    ├── auditoria_20260131.txt        # Output real
    └── grafana_screenshots/          # Evidências
```

---

## Quer Contribuir?

Este projeto é open-source! Se você quiser ajudar:

- Reporte bugs ou problemas que encontrar
- Sugira melhorias nos scripts
- Ajude a melhorar a documentação
- Dê uma star se achou útil!

---

## Contato

**Marcelo Loiola**  
Software Architect | DevOps Engineer | Cloud Engineer

- **Email:** marceloloiola.ti@gmail.com
- **WhatsApp:** +55 61 98408-6866
- **LinkedIn:** [linkedin.com/in/marcelo-loiola](https://linkedin.com/in/marcelo-loiola)
- **GitHub:** [github.com/marceloloiola](https://github.com/marceloloiola)

---

## Licença

Este projeto está sob a licença MIT. Sinta-se livre para usar, modificar e distribuir.

---

## Agradecimentos

Ferramentas e projetos que me inspiraram:
- [Vertical Pod Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
- [Goldilocks](https://github.com/FairwindsOps/goldilocks)
- [Kube-resource-report](https://github.com/hjacobs/kube-resource-report)

---

**"Otimizar não é sobre cortar recursos, é sobre usar recursos de forma inteligente."**

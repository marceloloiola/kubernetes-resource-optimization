# Screenshots do Grafana - Namespace Velero

Esta pasta contém evidências visuais da análise de métricas do Prometheus/Grafana que foram fundamentais para definir os novos valores de CPU requests.

## Screenshots Incluídos

### 1. node-agent Pods (DaemonSet)

**Arquivos:**
- `node-agent-cpu-7days.png` - Histórico de CPU por 7 dias
- `node-agent-memory-7days.png` - Histórico de Memória por 7 dias

**Observações:**
- Uso de CPU extremamente estável: ~0.0005 cpu (0.5m)
- Uso de memória constante: ~26-30 MiB
- Nenhum pico significativo detectado
- Padrão: Workload extremamente previsível

### 2. velero Pod (Deployment)

**Arquivos:**
- `velero-cpu-7days.png` - Histórico de CPU por 7 dias
- `velero-memory-7days.png` - Histórico de Memória por 7 dias

**Observações:**
- Uso médio de CPU: ~0.005 cpu (5m)
- Picos ocasionais: até 0.015 cpu (15m)
- Picos correlacionados com execução de backups
- Memória estável: ~216-256 MiB

## Como Usar

### Adicionar Screenshots

1. Capture screenshots do Grafana mostrando:
   - Painel de CPU Utilization
   - Painel de Memory Utilization
   - Período: últimos 7 dias
   - Resolução: suficiente para ver detalhes

2. Nomeie os arquivos seguindo o padrão:
   ```
   <pod-name>-<metric>-<period>.png
   
   Exemplos:
   - node-agent-cpu-7days.png
   - velero-memory-30days.png
   - velero-cpu-peak-detail.png
   ```

3. Coloque os arquivos nesta pasta

### Métricas Recomendadas

**CPU:**
```promql
# Uso de CPU por container
rate(container_cpu_usage_seconds_total{namespace="velero"}[5m])

# CPU Throttling
rate(container_cpu_cfs_throttled_seconds_total{namespace="velero"}[5m])
```

**Memória:**
```promql
# Uso de memória
container_memory_working_set_bytes{namespace="velero"}

# Uso vs Request
container_memory_working_set_bytes{namespace="velero"} / 
on(pod) group_left kube_pod_container_resource_requests{namespace="velero", resource="memory"}
```

## Template de Análise

Para cada screenshot, documente:

```markdown
### Screenshot: node-agent-cpu-7days.png

**Período:** 24/01/2026 - 31/01/2026
**Pods analisados:** 3 (node-agent-xxx)

**Métricas observadas:**
- Uso médio: 0.5m
- Uso P95: 0.7m
- Uso máximo: 1.0m
- Padrão: Estável, sem variação

**Conclusão:**
Request de 5m oferece margem de 5-10x, adequado para DaemonSet crítico.

**Request recomendado:** 5m (anteriormente 20m)
```

## Valor das Evidências

Esses screenshots são essenciais para:

1. **Justificar decisões técnicas** com dados reais
2. **Demonstrar análise rigorosa** antes de mudanças
3. **Comparar antes/depois** da otimização
4. **Compartilhar conhecimento** com o time
5. **Auditar decisões** no futuro

## Como Capturar

### No Grafana:

1. Acesse o dashboard relevante
2. Selecione o período desejado (7 ou 30 dias)
3. Clique no ícone de câmera ou use:
   - Keyboard: `Ctrl + Shift + E` (export)
   - Menu: Panel → Share → Direct link rendered image
4. Salve a imagem com nome descritivo

### Alternativa - CLI:

```bash
# Usando grafana-image-renderer
curl -H "Authorization: Bearer YOUR_API_KEY" \
  "http://grafana.domain.com/render/d/dashboard-id/dashboard-name?width=1200&height=600&from=now-7d&to=now" \
  -o screenshot.png
```

## Segurança

**Atenção:**
- Remova informações sensíveis antes de compartilhar
- URLs internas, IPs, nomes de domínio
- Credenciais ou tokens
- Dados de clientes

## Estrutura de Arquivos

```
grafana/
├── README.md                          # Este arquivo
├── node-agent-cpu-7days.png          # (ainda vou adicionar)
├── node-agent-memory-7days.png       # (ainda vou adicionar)
├── velero-cpu-7days.png              # (ainda vou adicionar)
├── velero-memory-7days.png           # (ainda vou adicionar)
├── cluster-overview.png              # (opcional)
└── dashboard-config.json             # (opcional)
```

## Contribuindo

Ao adicionar screenshots:

1. **Qualidade:** Alta resolução, legível
2. **Contexto:** Inclua títulos e eixos visíveis
3. **Período:** Especifique no nome do arquivo
4. **Documentação:** Atualize este README com análise

---

**Nota:** Esta pasta está vazia inicialmente. Adicione seus screenshots do Grafana para enriquecer a documentação do projeto.

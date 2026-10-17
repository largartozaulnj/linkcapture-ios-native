# Compatibilidade e testes pendentes

Um projeto, um bundle, mínimo iOS 16.0. Não há bloqueio por modelo, nem escolha de API baseada no nome do iPhone. `#available` verifica o sistema instalado em execução.

| Família alvo | Modelos | Situação de validação |
|---|---|---|
| 14 | 14, 14 Plus, 14 Pro, 14 Pro Max | Código preparado; teste físico/simulador pendente |
| 15 | Todas as variantes, incluindo Plus/Pro/Pro Max | Código preparado; teste físico/simulador pendente |
| 16 | Todas as variantes, incluindo Plus/Pro/Pro Max e 16e | Código preparado; teste físico/simulador pendente |
| 17 | Toda a família, incluindo Pro e Pro Max; iPhone Air também sem restrição de código | Código preparado; teste físico/simulador pendente |

Não existe expectativa de instalar iOS 16 em modelos que saíram com uma versão posterior. A versão mínima permite iPhone 14 ainda no iOS 16; o mesmo binário roda em versões posteriores quando compilado/assinado corretamente.

## APIs usadas e alternativa

| API | Disponibilidade relevante | Uso/fallback |
|---|---|---|
| WKWebView, WKNavigationDelegate, WKUIDelegate | Anterior a iOS 16 | Navegação normal em todos os alvos |
| WKWebsiteDataStore.nonPersistent | Anterior a iOS 16 | Isolamento de cookies da sessão |
| WKWebsiteDataStore.proxyConfigurations | iOS 17+ no cabeçalho público WebKit | Guard de disponibilidade; nunca chamada em iOS 16 |
| Network.ProxyConfiguration, SOCKSv5, credencial, allowFailover | iOS 17+ | Usado somente após guard iOS 17 |
| NWListener/NWConnection/NWPathMonitor | Anterior a iOS 16 | Loopback, TCP e observação Wi-Fi/celular |
| URLSession async/await | iOS 15+ | DoH no iOS 16+ |
| NavigationStack/LabeledContent/SwiftUI | iOS 16+ | Base do layout nativo |
| SecTrustEvaluateWithError | Anterior a iOS 16 | Sem aceitação de trust inválido |

Fallback iOS 16: um reteste GET pela rede normal e diagnóstico DoH separado. Não existe uma API pública equivalente para trocar o DNS das conexões HTTPS do WKWebView nessa versão. Não reescrever URL com IP, não trocar certificado e não usar API privada. A alternativa externa é DNS gratuito no sistema/rede ou atualizar o iOS quando possível.

## Matriz automatizada preparada

- Deployment target 16.0 checa o compilador quanto a uso desprotegido de API mais recente.
- PolicyTests: preservação de URLs/escapes/parâmetros, rejeição de esquemas/credenciais, bloqueio de IPs especiais e leitura de NXDOMAIN.
- CompatibilityTests: inicialização do modelo e WKWebView, capacidade escolhida por runtime, safe area e screenshot nativo inicial.
- NetworkTests (opt-in): navegação normal, transporte HTTPS pelo SOCKS real, NXDOMAIN, certificado expirado, baseline direto e recuperação do domínio real.
- Jobs solicitam runtimes 16/17/18/26. Só executam o que estiver instalado; ausências geram `NOT-TESTED.txt`, não resultados aprovados. Jobs de compatibilidade fazem smoke/layout e políticas, não comprovam recuperação de rede.
- `full_device_matrix=true` executa políticas e smoke/layout nos modelos 14–17/Air encontrados. Nenhuma combinação inexistente de hardware/runtime é criada para fingir cobertura.

## Validação manual obrigatória

Em pelo menos iPhone 14 (notch), 14 Pro (Dynamic Island), um 15/16 e 17 Pro Max, com sistemas que cada modelo suporta:

1. Abrir/colar URL, teclado, voltar/avançar, atualizar, cancelar e restaurar último endereço.
2. Vertical/horizontal, tamanhos de texto maiores, safe areas, controles recolhidos e captura nativa. Inspecionar screenshots do job; teste de bounds não garante ausência de sobreposição visual.
3. Wi-Fi e dados móveis: example.com normal, `?sd=3`, HTTP, HTTPS, redirecionamento HTTP e JavaScript, mudança Wi-Fi/celular durante carregamento.
4. Domínio reservado `.invalid`: registrar falha, nunca sucesso; certificado expirado deve falhar também no proxy.
5. `62qpix.vip`: primeiro direto, depois recuperação. Só registrar equivalência ao Android se atingir `/launch` e conteúdo correto na mesma rede. Não presumir que HTTP 200 basta.
6. Banners, pop-ups de usuário, pop-ups automáticos bloqueados, links externos para apps e subrecursos/WebSockets. Proxy TCP não reproduz UDP/QUIC.
7. Suspender/resumir app, pouca memória e encerramento de processo WebKit. A aplicação deve oferecer reabertura, sem prometer impedir todo encerramento pelo iOS.
8. Renovar assinatura gratuita e abrir com Windows desligado depois de instalada/assinada.

## Evidência atual

Verificações locais Windows: estrutura de Info.plist e scheme XML; script Python sintaticamente válido; inspeção de guards iOS 17; DNS/HTTPS externo registrado em JSON. Nenhuma compilação Swift, teste XCTest ou execução no iPhone foi concluída ainda. O Windows não tem Xcode; execução no GitHub depende de login e disponibilidade do repositório autorizado.

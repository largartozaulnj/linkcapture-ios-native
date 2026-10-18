# LinkCapture iOS nativo — experimental

Projeto independente Swift/SwiftUI + WKWebView, iPhone arm64, mínimo **iOS 16.0**. Interface responsiva, safe areas, navegação interna, barra de endereço, voltar/avançar, início, atualizar/parar, diagnóstico e controles recolhíveis. URLs, caminhos e parâmetros são preservados. PWA e Android não foram alterados; não há VPS ou mensalidade.

## Assinatura e atualizações — 0.2.0 (2)

[Fonte oficial e botão Adicionar ao AltStore](https://largartozaulnj.github.io/linkcapture-ios-native/) · [source.json](https://largartozaulnj.github.io/linkcapture-ios-native/source.json) · [Guia completo](ASSINATURA-E-ATUALIZACOES.md). Catálogo gerado a partir do Info.plist e dos bytes reais da IPA, com histórico, tamanho e SHA-256. Atualizações exigem sua autorização no AltStore.

Menu → Assinatura e Atualizações: informe o vencimento real exibido pelo AltStore, confirme em RENOVEI PELO ALTSTORE e autorize as notificações. Lembretes locais de 6 a 0 dias, horário configurável, funcionam offline após agendamento. Abrir o app não estende a validade. A leitura automática confiável do prazo não foi implementada; a data é manual. Assinatura gratuita ainda precisa de renovação pelo AltServer. Associação da fonte, atualização preservando dados e entrega das notificações precisam de validação no iPhone real.

## Interface atualizada

Barra de endereço compacta e arredondada, domínio atual e edição da URL completa ao tocar, abrir pelo botão/teclado, carregamento discreto e atualizar/parar. Navegação inferior com voltar, avançar, início, atualizar e menu. Diagnóstico, conexão, copiar, compartilhar, colar e recolher ficam no menu. Sem título/corrente no cabeçalho, segunda barra de status ou marca Google. Layout escuro com acento próprio e safe areas do iPhone.

Motor, wrapper WKWebView, SOCKS, DNS, TLS, política de URLs, Bundle ID, projeto e assinatura preservados. Comparação SHA-256 nos commits em visual-engine-integrity.json. Detalhes em ATUALIZACAO-VISUAL.md. Testes de layout compacto/largo aprovados após corrigir compressão das barras; alturas de toque permanecem fixas, e o viewport ocupa o restante.

## Download e resultado real

- [Prévia corrigida e IPA unsigned](https://github.com/largartozaulnj/linkcapture-ios-native/releases/tag/experimental-run-39085485364)
- [Build e testes](https://github.com/largartozaulnj/linkcapture-ios-native/actions/runs/39085485364)
- [Instalar pelo Windows](INSTALAR-NO-WINDOWS.md)

Build iPhone aprovado com **Xcode 16.4 / SDK 18.5**, deployment target **16.0**, commit `b5bfd425eba3f04783648f290c65dd2127d4bdbb`. Quinze testes unitários de políticas, renovação, catálogo e inicialização/layout aprovados; cobertura nos runtimes disponíveis iOS 18 e 26. Runtimes 16/17 ausentes: **NÃO TESTADOS**. Validação física da interface reformulada ainda pendente.

**Rede no simulador iPhone 16 Pro / iOS 18.5: 5 de 6 testes aprovados.** Passaram navegação normal com `?sd=3`, transporte HTTPS real pelo proxy local, rejeição de certificado expirado, NXDOMAIN e registro do baseline direto. O baseline só registra observações, sem exigir sucesso.

**No simulador do GitHub, 62qpix.vip não reproduziu o destino /launch.** DNS alternativo resolveu o domínio, o proxy conectou por HTTPS e carregou subrecursos, mas a URL terminou em `/405`, não `/launch`. Essa asserção permanece reprovada; o workflow geral fica vermelho corretamente. A rota `/405` não deve ser confundida com status HTTP 405. A razão da diferença não foi determinada. IP da nuvem, políticas do site e diferenças de cliente são hipóteses, não conclusões.

A prévia anterior tinha SIGSEGV no setter Swift de proxy em iOS 18.5. A correção usa as funções C públicas de Network e a propriedade pública marcada `NS_REFINED_FOR_SWIFT` no WebKit, importada como `__proxyConfigurations`. Não usa KVC, selectors privados ou desativação TLS. Os seis testes de rede executaram após a correção. Use o IPA da prévia corrigida. As pastas de fontes e o projeto Xcode são a referência atual; o ZIP de bootstrap antigo da raiz é obsoleto.

## Recuperação e limites

| Sistema instalado | Comportamento |
|---|---|
| iOS 16 | WKWebView direto, reteste GET limitado e DoH informativo. Não muda o DNS real do WebKit. |
| iOS 17+ | Proxy SOCKS5 local experimental, autenticação aleatória, DoH Cloudflare/Google e TCP por IP público validado. Guard `#available(iOS 17.0, *)` em toda API nova. |

Um único projeto atende as famílias iPhone 14, 15, 16 e 17, incluindo Plus/Pro/Pro Max e modelos compatíveis. Isso é alvo de compatibilidade, não certificação em todos os aparelhos. Modelos recentes não podem instalar versões anteriores ao seu sistema de lançamento.

WKWebView → SOCKS5 autenticado em loopback no próprio iPhone → DoH → TCP ao IP público. URL e hostname permanecem intactos; WebKit gera SNI e valida certificados. O proxy não descriptografa HTTPS, não instala certificados e não faz MITM. `allowFailover=false` impede conexão direta silenciosa no modo proxy. A propriedade pública refinada evita o wrapper Swift que falhou no teste, mantendo a mesma API documentada.

Listener loopback, porta efêmera, até 64 conexões, buffers de 64 KiB, backpressure, limites de conexão/inatividade, somente portas 80/443. IPs privados/especiais são recusados no proxy; IPv6 é conservador. Não há UDP/QUIC, VPN, controle do DNS do sistema ou serviço persistente em segundo plano. Suspensão pelo iOS pode interromper conexões. Rede celular, troca de rede e retomada precisam de teste físico.

Retestes limitados, sem reenvio automático de POST; durante recuperação: “REABRINDO LINK... AGUARDE”. Erros DNS, TLS, conexão, HTTP e URLs ficam no diagnóstico. Evidência DOM é heurística, não prova universal de conteúdo correto. O usuário pode confirmar visualmente; HTTP 200 sozinho não significa sucesso. Certificados inválidos continuam recusados. Esquemas externos e pop-ups automáticos são bloqueados; links de usuário para nova janela usam a view interna.

Recriar WKWebView para aplicar proxy pode perder histórico; cookies ficam no mesmo data store não persistente. Último endereço é salvo localmente. Diagnósticos ficam em memória e só são copiados por ação do usuário; URLs podem conter parâmetros sensíveis.

## Compilar gratuitamente

O repositório público já contém `.github/workflows/ios.yml`, projeto Xcode e fontes. GitHub Actions usa runners padrão macOS, sem conta Apple ou certificados. Push em main compila IPA unsigned e testes unitários. Actions → Build experimental iOS → Run workflow executa rede e matriz de compatibilidade. Ausência de runtime gera NOT-TESTED.txt, não aprovação fictícia. O artifact preserva IPA e xcresult mesmo quando o teste real falha.

`distribute.yml` publica o binário já compilado e BUILD-INFO.json após conferir build/unitários. Se a criação da tag for recusada ao token automático, crie a prévia pela interface do GitHub apontando ao commit compilado e repita apenas a publicação. `diagnostics.yml` exporta resumos e observações dos xcresult sem repetir navegação.

No Mac, abra LinkCapture.xcodeproj, scheme LinkCapture. SDK precisa reconhecer APIs iOS 17+, mesmo com deployment target 16. Para assinatura por Xcode, use Personal Team e bundle ID próprio. Não exige Network Extension ou entitlement pago.

## Instalação e próximos testes

A IPA é unsigned e exige assinatura local pelo AltStore Classic; não instala por simples download no Safari. Siga INSTALAR-NO-WINDOWS.md. Assinatura gratuita normalmente expira em sete dias; Windows/AltServer é necessário para instalar/renovar, não para navegar depois.

Teste primeiro example.com/?sd=3, depois 62qpix.vip direto e pelo proxy, sem forçar /launch e chamar isso de redirecionamento. Compare Wi-Fi e dados móveis e o APK Android na mesma rede. Código Android V1.2 não foi fornecido, portanto equivalência não foi comprovada. Banners, pop-ups, orientação, safe area, retomada e dispositivos antigos precisam de inspeção física; veja COMPATIBILIDADE.md.

No iOS 16, a alternativa gratuita para DNS é configuração da rede Wi-Fi ou aplicativo oficial de DNS/VPN compatível; não é uma recuperação feita pelo LinkCapture. Para /405, trocar DNS novamente não garante remover uma decisão do site. A melhor próxima validação gratuita é o IPA no iPhone real, na mesma rede do Android.

## Fontes oficiais

- [Cabeçalho público WKWebsiteDataStore](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebsiteDataStore.h)
- [Apple: proxies WebKit](https://developer.apple.com/videos/play/wwdc2023/10002/)
- [Apple: nw_proxy_config_create_socksv5](https://developer.apple.com/documentation/network/nw_proxy_config_create_socksv5(_:))
- [GitHub: runners](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)
- [AltStore Windows](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
- [AltStore: expiração e limites](https://faq.altstore.io/altstore-classic/your-altstore)

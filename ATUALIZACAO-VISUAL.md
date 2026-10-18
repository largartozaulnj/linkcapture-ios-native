# Interface nativa compacta

Mudança visual isolada em LinkCaptureApp.swift. Bundle ID, assinatura, projeto Xcode, BrowserModel, LocalSOCKSProxy, DNSResolver, URLPolicy e Info.plist preservados. visual-engine-integrity.json compara por SHA-256 os arquivos protegidos dos commits compilados anterior e novo.

- Removidos título e corrente do cabeçalho principal.
- Barra superior arredondada de 44 pontos, domínio compacto e edição da URL completa ao tocar. Abrir pelo botão ou pelo teclado; indicador discreto de carga e atualizar/parar.
- Barra inferior com voltar/avançar desabilitados conforme histórico, início, atualizar/parar e menu.
- Menu com diagnóstico DNS, informações da conexão, copiar, compartilhar nativo, colar, atualizar, recolher e ajuda.
- WKWebView ocupa o espaço entre as barras, sem mudança de escala, viewport, delegate, rolagem ou zoom. Não existe segunda barra de status.
- Safe areas e ajuste normal do SwiftUI ao teclado, sem ignorar a safe area do teclado. Animação de recolhimento respeita Reduzir Movimento.
- Cores escuras neutras, acento próprio; sem marcas ou logotipos Google.

## Verificação

Testes de layout verificam posição do WKWebView entre as barras, largura contida na safe area e renderizações compacta/larga. As dimensões simuladas são testes de layout, não certificação física de orientação/teclado em cada modelo.

O workflow repete PolicyTests, CompatibilityTests e NetworkTests, incluindo 62qpix.vip, HTTPS pelo proxy e certificado inválido. A navegação real usa o mesmo motor; o teste de /launch continua exigente e não é alterado para esconder respostas do site.

No iPhone, conferir teclado URL e botão Abrir; voltar/avançar; atualizar/parar; menu Compartilhar; vertical/horizontal; safe area; controles recolhidos e recuperação do link na mesma rede que já funcionou. Instalar via AltStore com o mesmo procedimento e o mesmo Bundle ID.

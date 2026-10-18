# Instalar no iPhone pelo Windows sem conta Developer paga

Estado: atualização visual; mesma identidade do aplicativo. Build aprovado; IPA experimental destinada à assinatura pelo mesmo AltStore Classic. Instalação e assinatura no iPhone ainda não executadas.

Download direto: https://github.com/largartozaulnj/linkcapture-ios-native/releases/download/experimental-run-39082906544/LinkCapture-experimental-UNSIGNED.ipa

Página da prévia e BUILD-INFO.json: https://github.com/largartozaulnj/linkcapture-ios-native/releases/tag/experimental-run-39082906544

1. Depois que o workflow passar, abra a execução no GitHub Actions e baixe o artifact `LinkCapture-experimental-and-test-results`. Descompacte; procure `LinkCapture-experimental-UNSIGNED.ipa`. Confira a execução e o commit correspondente antes de instalar.
2. No Windows, siga o guia oficial para instalar **AltServer + AltStore Classic**: https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows . Instale as versões de iTunes/iCloud indicadas no guia; não use tutoriais com certificados compartilhados ou ferramentas desconhecidas.
3. Conecte o iPhone por USB, desbloqueie, autorize o pareamento e escolha AltServer → Install AltStore → seu aparelho. Entre com sua conta Apple somente na ferramenta local. Não envie conta/senha/código ao chat nem ao GitHub.
4. No iPhone, siga a solicitação de confiança do perfil e habilite Modo de Desenvolvedor, quando exigido, em Ajustes → Privacidade e Segurança. O iOS pode exigir reinício e confirmação.
5. Copie a IPA para o aplicativo Arquivos do iPhone por um meio de sua preferência. Abra AltStore Classic → My Apps → `+` e selecione a IPA. AltStore fará a assinatura de desenvolvimento gratuita e a instalação. A IPA unsigned não é instalável diretamente por Safari ou simples download.
6. Abra LinkCapture. Teste `https://example.com/?sd=3` e depois `https://62qpix.vip`. No Diagnóstico, compare modo direto e proxy local (somente iOS 17+). Registre URL final, erro, estratégia e conteúdo visível. Testar `/launch` explicitamente não comprova que houve redirecionamento automático.

## Renovação

A assinatura gratuita do AltStore Classic normalmente expira após sete dias; renove antes de vencer usando AltServer. Existe limite de três apps sideloaded gratuitos simultâneos e restrições de App IDs. Referência oficial: https://faq.altstore.io/altstore-classic/your-altstore .

Windows/AltServer precisam estar disponíveis para instalar e renovar. **Depois de instalado, com assinatura válida, LinkCapture navega no próprio iPhone e não depende do Windows ligado.** Não há assinatura gratuita permanente neste fluxo. Não é necessário contratar Apple Developer, VPS, domínio ou plano pago.

## Se falhar

- Build sem IPA: verificar logs do Actions; não renomear um ZIP de fontes para `.ipa`.
- IPA sem assinatura válida: importar pelo AltStore, em vez de tentar instalar o pacote unsigned diretamente.
- Limite de apps/App IDs: resolver no AltStore e aguardar a janela da Apple, conforme a mensagem; não comprar certificados compartilhados.
- Certificado HTTPS do site inválido: não será ignorado; a recuperação deve encerrar.
- iOS 16: navegação interna funciona como objetivo de compatibilidade; proxy do WKWebView não está disponível. Há reteste direto e DoH informativo. Essa limitação não é resolvida pela assinatura do aplicativo.

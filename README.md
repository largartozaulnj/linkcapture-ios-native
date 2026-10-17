# LinkCapture iOS nativo — experimental 0.1

Projeto independente em Swift/SwiftUI + WKWebView. Mínimo **iOS 16.0**, iPhone arm64. Uma aplicação para iPhone 14/14 Plus/14 Pro/14 Pro Max e todas as variantes das famílias 15, 16 e 17, incluindo Pro Max. Não há restrição por nome de modelo nem resolução fixa. A compatibilidade é um alvo de desenvolvimento, ainda não uma certificação de teste em todos os aparelhos.

**Estado atual: código e projeto Xcode preparados; compilação macOS, IPA e testes iOS ainda não executados.** Nenhum resultado Windows é apresentado como prova de funcionamento em iPhone. O PWA anterior e o Android não foram modificados. Não há VPS, API paga, servidor remoto nem mensalidade de infraestrutura.

## O que foi implementado no código

- WKWebView interno real, barra de endereço, colar, voltar, avançar, início, atualizar/parar, gestos nativos, rotação e controles recolhíveis.
- URL HTTP/HTTPS, caminhos e parâmetros preservados. Esquemas externos automáticos e pop-ups automáticos bloqueados. Links target=_blank acionados pelo usuário abrem na mesma view.
- Observação de URL atual/final, redirecionamentos HTTP e navegações principais, HTTP principal, erros WebKit/URL loading, validação de confiança TLS, eventos TCP e resultados DoH.
- Retestes limitados, sem reenvio automático de POST, sem loop infinito. Enquanto recupera: “REABRINDO LINK... AGUARDE”, com cancelamento.
- HTTP de erro não é tratado como sucesso. Evidência DOM é apenas heurística; diagnóstico exige confirmação visual para afirmar conteúdo correto. Uma página 200 com erro visual pode escapar à heurística — não há detector universal.
- Relatório mantido em memória e copiado somente por ação do usuário. URLs podem conter parâmetros sensíveis. Cookies/sessão no data store não persistente; último endereço salvo localmente.

## Compatibilidade por versão

| iOS instalado | Navegação interna | Recuperação disponível |
|---|---|---|
| 16.x | WKWebView | Uma nova tentativa direta; DoH informativo, sem mudar o DNS real do WebKit |
| 17.x, 18.x, 26.x e posteriores compatíveis | WKWebView | Proxy SOCKS5 local + DNS alternativo experimental, sujeito a validação real |

Cada acesso a `WKWebsiteDataStore.proxyConfigurations` / `Network.ProxyConfiguration` está protegido por `#available(iOS 17.0, *)`. No iOS 16, não são usados selectors privados, KVC, swizzling, URLProtocol para fingir interceptação de WKWebView, troca da URL HTTPS por IP, ou relaxamento de certificados.

No iOS 16, a alternativa gratuita para falha do DNS do sistema é configurar DNS na rede Wi-Fi (Cloudflare 1.1.1.1/1.0.0.1 ou Google 8.8.8.8/8.8.4.4), ou avaliar o aplicativo oficial 1.1.1.1 para conexão celular. Isso ocorre fora do LinkCapture. Atualizar para iOS 17+ permite experimentar o proxy por app, quando a atualização estiver disponível para o aparelho.

## Como o proxy local funciona (iOS 17+)

WKWebView → SOCKS5 autenticado em 127.0.0.1:porta efêmera no próprio iPhone → DoH Cloudflare/Google → socket TCP para IP público validado.

O hostname continua na URL e no TLS gerado pelo WebKit. O proxy transporta bytes, não faz MITM, não instala certificados e não descriptografa HTTPS. A verificação do certificado continua sob o sistema/WebKit. A conexão ao IP literal evita uma segunda resolução entre validação e conexão. IPs não são fixados no aplicativo: são consultados novamente com TTL limitado.

O listener é loopback e usa credencial aleatória por execução. Até 64 conexões, buffers de 64 KiB com backpressure, tempo limite de conexão e inatividade. Apenas TCP nas portas 80/443 e destinos públicos. UDP/QUIC, SOCKS BIND/UDP ASSOCIATE, portas arbitrárias e destinos internos são recusados. A política IPv6 é conservadora, limitada a global unicast e exclui algumas faixas especiais/transicionais; pode recusar endereços legítimos raros. Não é um proxy de uso geral.

O WK data store é configurado antes de criar a view de recuperação e `allowFailover=false` impede fallback silencioso para conexão direta nesse modo. **Ainda é necessário comprovar que o WebKit daquela versão envia o hostname ao SOCKS e que todos os recursos relevantes seguem o caminho esperado.** Não existe aqui firewall/VPN do sistema que controle tráfego de outros apps.

Reconstruir a view para aplicar proxy pode perder o histórico voltar/avançar; cookies da sessão permanecem no mesmo data store. Links posteriores continuam no modo proxy até selecionar “Voltar ao modo direto”. Sessões não executam como serviço persistente em segundo plano: suspensão/encerramento pelo iOS pode interromper conexões. O usuário pode reabrir o link em primeiro plano.

## Caso real 62qpix.vip — o que foi observado

Em 17/10/2026, na rede de execução Windows:

- DNS padrão: nome não encontrado.
- Google e Cloudflare DoH: CNAME para `zhu-6187298.l-g-m-2.com`, A `104.18.22.74` e `104.18.23.74`, além de AAAA. Registros podem mudar; não são hardcoded no app.
- Node HTTPS conectando a cada IP com `servername=62qpix.vip`, hostname preservado e `rejectUnauthorized=true`: TLS 1.3 autorizado e HTTP 200 em `/` e `/launch`.
- Não foi observado Location HTTP para `/launch`, nem foi executada renderização/JavaScript nesse teste. O título retornado era vazio. **HTTP 200 não comprova página correta, redirecionamento ou equivalência ao APK.**
- O curl Windows falhou no Schannel antes do handshake (SEC_E_NO_CREDENTIALS). Esse erro foi do cliente de teste; não foi classificado como certificado inválido do site. O teste Node foi usado em seguida, sem desativar validação TLS.

Os JSONs nesta pasta registram as observações. Ainda não há validação no WKWebView nem comparação com Android V1.2, cujo código não foi fornecido. Outros projetos LinkAutoTester localizados não foram usados como substitutos.

## Compilar gratuitamente no GitHub Actions

1. Crie um repositório novo **público**, somente para esta pasta. Os runners macOS padrão do GitHub são gratuitos em repositórios públicos, sujeitos à política de uso. Não use runners Large/XL nem serviços pagos. Repositórios privados têm franquias diferentes e não são o caminho proposto.
2. Pelo GitHub Desktop no Windows, adicione esta pasta como repositório local, faça um commit e publique no repositório público. Inclua `.github/workflows/ios.yml` e `LinkCapture.xcodeproj`. Não publique a pasta inteira da conversa, credenciais Apple, certificados ou projetos Android.
3. O primeiro push em `main` inicia compilação sem assinatura e testes unitários. Para rede/compatibilidade, vá a Actions → Build experimental iOS → Run workflow; mantenha `network_tests=true`. Opcionalmente ative `full_device_matrix`.
4. Baixe o artifact `LinkCapture-experimental-and-test-results`. Ele conterá a IPA **se a compilação passar**, e os `.xcresult` produzidos. Um artifact por si só não significa testes aprovados; leia o status de cada etapa.
5. A IPA `LinkCapture-experimental-UNSIGNED.ipa` é um pacote para assinatura posterior; não instala diretamente no iPhone. O GitHub não precisa de seu Apple ID nem de certificados para esse build.

O workflow usa `macos-15` para build e jobs padrão `macos-15`/`macos-26` para inventário de compatibilidade. Xcode e runtimes mudam no GitHub: o workflow registra a versão real e nunca apresenta iOS 16/17 como testado se o runtime não estiver instalado. Pode ser necessário outro Mac com runtime compatível para preencher essa cobertura antiga. Não inventa um dispositivo iOS 16 em um iPhone que não suporta essa versão.

## Instalar pelo Windows, sem App Store

Use **AltStore Classic**, não AltStore PAL. Siga a documentação oficial atual para sua versão do Windows/iOS:

1. Instale as dependências Apple exigidas pelo guia oficial (iTunes/iCloud; o guia distingue versões Microsoft Store e download Apple).
2. Baixe AltServer somente do site oficial, conecte o iPhone por USB, desbloqueie e autorize o pareamento. Configure sincronização Wi-Fi se desejar renovar sem cabo na mesma rede.
3. No AltServer, escolha Install AltStore → seu iPhone. Informe sua conta Apple somente no fluxo local da ferramenta, nunca no chat ou no GitHub.
4. No iPhone, confie no perfil correspondente em Ajustes → Geral → VPN e Gerenciamento de Dispositivo; ative Modo de Desenvolvedor quando solicitado e siga os reinícios/avisos do iOS.
5. Transfira a IPA gerada para Arquivos no iPhone. No AltStore Classic → My Apps → `+`, selecione a IPA; a ferramenta deve reassinar e instalar com sua conta gratuita. O fluxo precisa ser validado com a IPA real, ainda não gerada neste ambiente.
6. Teste primeiro `https://example.com/?sd=3`; depois `https://62qpix.vip`. Abra Diagnóstico e compare modo direto e proxy. Não force `/launch` e chame isso de redirecionamento: o botão de /launch serve como teste separado.

**Assinatura gratuita normalmente expira em 7 dias.** AltStore Classic tem limite de três apps assinados gratuitos simultaneamente (incluindo normalmente o próprio AltStore), além de limites de App IDs. Renove com AltServer antes de expirar. Windows/AltServer precisam estar disponíveis para instalação/renovação, **não durante a navegação**. Não há solução oficial de assinatura gratuita permanente por este fluxo. Se renovar pelo Windows for incompatível com seu uso, avaliar SideStore separadamente; não está configurado nem validado aqui.

## Abrir no Xcode (Mac)

Abra `LinkCapture.xcodeproj`, scheme LinkCapture. Selecione um simulador disponível e Build. Para dispositivo com Xcode, escolha seu Personal Team e um bundle ID exclusivo em Signing & Capabilities. O projeto não exige Network Extension, App Groups, certificado distribuído ou entitlement pago. SDK de compilação precisa ser iOS 17+ para reconhecer os símbolos, mesmo com deployment target iOS 16.

Exemplo de build unsigned:

```sh
xcodebuild -project LinkCapture.xcodeproj -scheme LinkCapture -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO build
```

## Plano de validação

Veja `COMPATIBILIDADE.md`. Os testes XCTest estão preparados, **não executados**. O teste de 62qpix exige URL final host `62qpix.vip`, caminho `/launch`, resposta HTTP apropriada e evidência DOM; um 200 vazio falha. Mesmo um teste automatizado aprovado não substitui inspeção visual, uso dos banners/pop-ups e comparação com Android na mesma rede.

## Fontes oficiais

- WebKit, disponibilidade real no cabeçalho: https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebsiteDataStore.h
- Apple, proxy do WebKit: https://developer.apple.com/videos/play/wwdc2023/10002/
- Apple, ProxyConfiguration: https://developer.apple.com/documentation/network/proxyconfiguration
- GitHub, runners padrão e gratuidade em repositórios públicos: https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job
- AltStore Windows: https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows
- AltStore, expiração e limites: https://faq.altstore.io/altstore-classic/your-altstore

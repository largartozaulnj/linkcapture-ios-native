# Fonte oficial e lembretes — 0.2.0 (2)

Fonte HTTPS: https://largartozaulnj.github.io/linkcapture-ios-native/source.json
Adicionar pelo Safari: https://largartozaulnj.github.io/linkcapture-ios-native/

## AltStore Classic

Abra a página, toque em Adicionar ao AltStore Classic e confirme a fonte. Ou cole o endereço source.json em Sources → +. Confira LinkCapture / org.linkcapture.experimental e a versão 0.2.0 (2). Se o aplicativo instalado manualmente aparecer associado, use Atualizar em My Apps; se não aparecer, confira a listagem da fonte e a identidade/conta usadas para assinar antes de continuar. Não desinstale para forçar associação. Essa migração e a preservação dos dados exigem verificação no iPhone. O projeto mantém o Bundle ID e os mesmos UserDefaults; a ferramenta de assinatura pode acrescentar o ID da equipe ao bundle reassinado.

A fonte não assina nem instala sozinha. Você autoriza a atualização no AltStore e ainda pode precisar do AltServer. Não há instalação automática implementada no LinkCapture. Não envie conta Apple, senha ou certificados ao GitHub.

GitHub Releases hospeda IPAs; GitHub Pages hospeda o JSON. pages.yml reconstrói o catálogo lendo Info.plist dentro de cada IPA e conferindo tamanho real. Publicações futuras usam version/buildVersion novos no Info.plist; distribute.yml publica a IPA e dispara a atualização do catálogo. Os artefatos anteriores 0.1.0 declaravam todos build 1: somente a prévia visual mais recente representa esse par, sem inventar versões históricas.

O esquema documentado do AltStore Classic não oferece campo SHA-256 de verificação. Os hashes ficam em integrity.json, sem afirmar que o AltStore os verifica. appPermissions declara apenas as permissões reais da IPA unsigned; notificações locais comuns não exigem entitlement de push ou alertas críticos.

## Validade e notificações

A data é manual, copiada da validade que o AltStore mostra e confirmada no app com data/hora. Não usamos a última abertura nem somamos sete dias automaticamente. A validade depende do perfil de provisionamento após a assinatura, não da data do IPA ou do certificado TLS. O iOS não fornece aqui uma API pública para consultar o estado privado de renovação de outro app. O formato CMS do perfil e uma extração de XML sem verificação não são tratados como fonte confiável. Esta versão escolhe o fallback manual, sem API privada nem credenciais Apple.

Menu → Assinatura e Atualizações → RENOVEI PELO ALTSTORE → confirme o vencimento real. Configurar lembretes → solicitar permissão → escolher horário (10h padrão), avisos 6–3 dias e urgentes 2/1/0. Desativar o botão principal cancela todos os lembretes do LinkCapture. Alterar a data ou configurações substitui os pedidos antigos usando identificadores estáveis, sem duplicar nem remover notificações de outros recursos.

São agendadas até sete notificações locais não repetitivas, antecipadamente, sem internet/Windows depois. No dia zero o horário é antecipado se necessário para ficar antes da expiração informada; avisos passados não são recriados. Contagem usa dias do calendário local. Mudando de fuso, abra o aplicativo para reagendar no novo horário local. Abrir o app não altera a data salva. Renovações feitas fora dele precisam de confirmação manual da nova data.

Urgente significa aviso comum com som; não contorna Foco, silencioso, permissões negadas ou ajustes do sistema. Não usamos alertas críticos ou time-sensitive sem entitlement. A entrega é controlada pelo iOS e não é garantida após expirar/desinstalar. Priorize os avisos de 2 e 1 dia antes.

## Validação física necessária

Confirmar no iPhone: adicionar/decodificar a fonte no AltStore, associação da instalação existente, atualização sem perder dados, permissão concedida/negada, som/Foco, edição de data/horário e entrega real offline. Os testes automatizados cobrem planejamento, horários, DST, datas desconhecidas/vencidas, renovação, persistência e comparação de versões; não substituem esses testes físicos.

Fontes: https://faq.altstore.io/developers/make-a-source ; https://faq.altstore.io/developers/updating-apps ; https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles ; https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app

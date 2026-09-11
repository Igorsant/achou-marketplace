## Template preenchido

### Projeto: `Achou! Marketplace`
### Equipe: `4`

---

### 🥇 Feature 1 — `Checkout via mensagem no WhatsApp`

- **Problema real que ela resolve:** Facilita o fechamento da compra ao conectar o comprador diretamente com o vendedor pelo WhatsApp, evitando a necessidade de implementar um sistema de pagamento completo no marketplace.
- **Critério(s) de prioridade que mais pesaram:** Viabilidade técnica, velocidade de entrega e conversão, pois permite transformar o carrinho em uma solicitação real de compra com baixo custo de implementação.
- **Em uma frase o que seria a aplicação utópica** (a versão completa, dos sonhos): Um checkout integrado ao WhatsApp que envia automaticamente o resumo do pedido, calcula frete, identifica o vendedor, acompanha a conversa e atualiza o status da compra.
- **E qual seria um MVP comercializavel?** (a menor versão possível, ponta a ponta, entregável em ~3 dias): Um botão no carrinho que monta uma mensagem com produtos, quantidades e valor total e abre uma conversa do WhatsApp com o contato do vendedor.

---

### 🥈 Feature 2 — `Adicionar produto ao carrinho e visualizar carrinho`

- **Problema real que ela resolve:** Permite que o comprador selecione produtos de interesse, confira os itens escolhidos e saiba quanto pretende comprar antes de entrar em contato com o vendedor.
- **Critério(s) de prioridade que mais pesaram:** Experiência do usuário, conversão e dependência do checkout, porque o carrinho organiza as informações que serão enviadas pelo WhatsApp.
- **O "elefante" dela** (a versão completa, dos sonhos): Um carrinho persistente e inteligente, com atualização de estoque, cupons, cálculo de frete, separação por vendedor, recomendações e sincronização entre dispositivos.
- **A primeira fatia** (a menor versão possível, ponta a ponta, entregável em ~3 dias): Adicionar produtos ao carrinho, visualizar nome, imagem, preço e quantidade, alterar quantidades, remover itens e calcular o total da compra.

---

### 🥉 Feature 3 — `Autenticação de dados via login`

- **Problema real que ela resolve:** Garante que os dados do usuário sejam identificados e protegidos, permitindo controlar o acesso às áreas que exigem conta, como o painel do vendedor.
- **Critério(s) de prioridade que mais pesaram:** Segurança, controle de acesso e confiabilidade dos dados, além da necessidade de identificar o vendedor responsável pelos produtos e pedidos.
- **O "elefante" dela** (a versão completa, dos sonhos): Um sistema de autenticação completo com cadastro, login, recuperação de senha, confirmação de e-mail, diferentes perfis, permissões e sessão persistente.
- **A primeira fatia** (a menor versão possível, ponta a ponta, entregável em ~3 dias): Criar uma tela de login com e-mail e senha, validar os dados no backend, gerar uma sessão autenticada e liberar o acesso ao painel protegido do vendedor.

---

### Ficou de fora (e por quê)

Listem pelo menos 2 features que a equipe considerou e decidiu **não**
priorizar agora. Uma linha de justificativa basta.

| Feature descartada | Por que não entrou entre as 3 |
| --- | --- |
| Cadastro e gerenciamento de produtos | É importante para abastecer a vitrine, mas pode ser tratado como uma etapa operacional posterior ao desenho do fluxo principal de compra. |
| Busca e visualização detalhada dos produtos | A vitrine é necessária, mas a prioridade inicial está em validar o caminho entre carrinho, checkout via WhatsApp e identificação do usuário. |

---

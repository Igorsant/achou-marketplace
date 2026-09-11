## Template preenchido

### Projeto: `Achou! Marketplace`
### Equipe: `4`

---

### 🥇 Feature 1 — `Checkout pelo aplicativo`

- **Problema real que ela resolve:** Permite que o comprador escolha a forma de pagamento no aplicativo e envie os dados do pedido para o vendedor, sem precisar organizar essas informações manualmente.
- **Critério(s) de prioridade que mais pesaram:** Conversão, praticidade para o comprador e viabilidade técnica, pois o app organiza o pedido e o pagamento pode ser confirmado por um canal externo.
- **Em uma frase o que seria a aplicação utópica** (a versão completa, dos sonhos): Um checkout completo no aplicativo, com endereço de entrega, cálculo de frete, cupons, diferentes formas de pagamento, confirmação automática e acompanhamento do pedido.
- **E qual seria um MVP comercializavel?** (a menor versão possível, ponta a ponta, entregável em ~3 dias): Uma tela de checkout que exibe o resumo do carrinho, coleta os dados de entrega, permite escolher o tipo de pagamento e envia o pedido ao vendedor pelo WhatsApp, que retorna com o link ou as instruções para confirmação do pagamento.

#### 3 entregas E2E

1. **Resumo, entrega e forma de pagamento:** o comprador abre o checkout a partir de um carrinho com produto, confere os itens, informa os dados básicos de entrega e escolhe entre as formas de pagamento disponíveis.
2. **Envio do pedido ao vendedor:** o comprador confirma o pedido no app e o sistema envia o resumo com os dados de entrega e a forma de pagamento escolhida ao vendedor pelo WhatsApp.
3. **Continuidade da confirmação:** o vendedor recebe o pedido, envia o link ou as instruções de pagamento pelo WhatsApp e o comprador visualiza no app o pedido como aguardando confirmação externa.

---

### 🥈 Feature 2 — `Adicionar produto ao carrinho e visualizar carrinho`

- **Problema real que ela resolve:** Permite que o comprador selecione produtos de interesse, confira os itens escolhidos e saiba quanto pretende comprar antes de entrar em contato com o vendedor.
- **Critério(s) de prioridade que mais pesaram:** Experiência do usuário, conversão e dependência do checkout, porque o carrinho organiza as informações que serão enviadas ao vendedor para dar continuidade ao pagamento.
- **O "elefante" dela** (a versão completa, dos sonhos): Um carrinho persistente e inteligente, com atualização de estoque, cupons, cálculo de frete, separação por vendedor, recomendações e sincronização entre dispositivos.
- **A primeira fatia** (a menor versão possível, ponta a ponta, entregável em ~3 dias): Adicionar produtos ao carrinho, visualizar nome, imagem, preço e quantidade, alterar quantidades, remover itens e calcular o total da compra.

#### 3 entregas E2E

1. **Adicionar e visualizar:** o comprador abre um produto, adiciona uma unidade ao carrinho e visualiza o item com nome, imagem, preço e quantidade.
2. **Editar a compra:** o comprador adiciona mais produtos, aumenta ou diminui quantidades, remove itens e vê o subtotal atualizado no carrinho.
3. **Preparar o checkout:** o comprador visualiza o carrinho completo, confere frete ou valor adicional simulado, vê o total final e segue para o checkout com os dados organizados.

---

### 🥉 Feature 3 — `Autenticação de dados via login`

- **Problema real que ela resolve:** Garante que os dados do usuário sejam identificados e protegidos, permitindo controlar o acesso às áreas que exigem conta, como o painel do vendedor.
- **Critério(s) de prioridade que mais pesaram:** Segurança, controle de acesso e confiabilidade dos dados, além da necessidade de identificar o vendedor responsável pelos produtos e pedidos.
- **O "elefante" dela** (a versão completa, dos sonhos): Um sistema de autenticação completo com cadastro, login, recuperação de senha, confirmação de e-mail, diferentes perfis, permissões e sessão persistente.
- **A primeira fatia** (a menor versão possível, ponta a ponta, entregável em ~3 dias): Criar uma tela de login com e-mail e senha, validar os dados no backend, gerar uma sessão autenticada e liberar o acesso ao painel protegido do vendedor.

#### 3 entregas E2E

1. **Login válido:** o usuário informa e-mail e senha, o backend valida as credenciais, cria a sessão e libera o acesso ao painel protegido.
2. **Erros e encerramento de sessão:** o usuário recebe uma mensagem para credenciais inválidas, consegue tentar novamente e pode sair da conta, retornando à tela de login.
3. **Sessão e proteção de acesso:** ao reabrir o app, a sessão válida é recuperada; sem autenticação, o usuário é impedido de acessar o painel e dados exclusivos do vendedor.

---

### Ficou de fora (e por quê)

Listem pelo menos 2 features que a equipe considerou e decidiu **não**
priorizar agora. Uma linha de justificativa basta.

| Feature descartada | Por que não entrou entre as 3 |
| --- | --- |
| Cadastro e gerenciamento de produtos | É importante para abastecer a vitrine, mas pode ser tratado como uma etapa operacional posterior ao desenho do fluxo principal de compra. |
| Busca e visualização detalhada dos produtos | A vitrine é necessária, mas a prioridade inicial está em validar o caminho entre carrinho, escolha do pagamento e confirmação externa. |

---

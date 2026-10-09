# Forja de Fichas

Criador de fichas de personagem para D&D 5e, feito com HTML, CSS e JavaScript puro. Visual preto com detalhes em vermelho e prata.

![Captura de tela do projeto](docs/screenshot.png)

**Demo:** https://arturcsantos1610.github.io/forja-de-fichas/

## O que faz

- **Rolagem de atributos** com quatro métodos: 4d6 descartando o menor, 2d6+6, compra de pontos (27 pontos) e distribuição padrão.
- **Escolha de classe** com distribuição sugerida dos valores, atributos principais destacados e ajuste manual limitado aos valores gerados.
- **Raças e antecedentes recomendados** para a classe escolhida, com ícones para quem está começando.
- **Escolha de armas** quando a classe oferece "qualquer arma simples" ou "duas armas marciais", com dano e propriedades na lista.
- **Tela de magias** para conjuradores, com truques e magias até o 3º círculo (166 magias do SRD), recomendações por classe, área, concentração e efeito de cada magia.
- **Retrato do personagem** na ficha, usado como capa em Minhas fichas e impresso no quadro de aparência do PDF.
- **Ajudantes de criação:** gerador de nome por raça e ideia de história a partir da classe e do antecedente.
- **Sugestões de personalidade:** traços, ideais, vínculos e fraquezas próprios para cada antecedente, com clique para adicionar e um botão de sorteio.
- **Ficha final** com perícias restantes, CA, pontos de vida, iniciativa, deslocamento, percepção passiva, ataques e CD de magia calculados.
- **Exportação** para a ficha oficial em PDF, já preenchida.
- **Ficha em jogo:** PV com dano, cura e PV temporários, salvaguardas contra a morte, espaços de magia, recursos de classe, dados de vida, condições, concentração, inspiração e descansos curto e longo, salvando sozinha.
- **Rolador de dados:** clique em testes, salvaguardas, perícias, iniciativa, ataques, dano e magias; vantagem e desvantagem, crítico, dados livres e expressões como 2d6+3, com histórico.
- **Minhas fichas:** salva as fichas para abrir, duplicar, exportar e importar depois. Sem login, ficam no navegador; com login, ficam na nuvem (Supabase) e aparecem em qualquer aparelho.
- **Compartilhar ficha por link:** link só de leitura para o mestre acompanhar a ficha e o estado em jogo, que pode ser desligado a qualquer momento.
- **Mesa do mestre:** reúne as fichas do grupo com CA, PV, percepção passiva, condições e concentração, e controla a iniciativa com criaturas, turnos, rodadas e dano.
- **Contas e perfil:** entrar, criar conta, trocar senha, nickname e emblema de perfil, e enviar as fichas do navegador para a conta.
- **Subir de nível** até o 5: PV pela média ou rolando o dado, aumento de atributo, subclasse do SRD, características novas, estilo de luta, especialização, invocações, dádiva do pacto, metamagia, presa do caçador, inimigo e terreno favoritos, terreno do druida, espaços de magia e magias novas, com opção de desfazer.
- **Livro do Jogador** com capítulos de raças, classes, antecedentes, equipamento (armas, armaduras, pacotes, itens, ferramentas e moedas com preços), atributos, combate, condições e conjuração, com lista de magias filtrável.

## Em desenvolvimento

- [x] Layout, abas e rolagem de atributos
- [x] Escolha de classe com distribuição sugerida
- [x] Raça com recomendações pela classe
- [x] Antecedentes e escolhas de equipamento e perícias
- [x] Ficha final com cálculos automáticos (CA, percepção passiva, deslocamento, CD de magia)
- [x] Exportação da ficha em PDF
- [x] Escolha de armas e tela de magias
- [x] Livro do Jogador por capítulos
- [x] Minhas fichas (salvas no navegador)
- [x] Subir de nível até o 5
- [x] Magias de 2º e 3º círculo e escolhas específicas de classe
- [x] Ficha em jogo e rolador de dados
- [x] Login para guardar as fichas na nuvem
- [x] Perfil, compartilhamento por link e mesa do mestre
- [ ] Inventário com compra de equipamento e carga
- [ ] App instalável que funciona sem internet
- [ ] Níveis 6 a 20
- [ ] Multiclasse e talentos

## Como rodar

Não precisa instalar nada, mas a exportação em PDF precisa que a página seja servida por um servidor (o navegador bloqueia a leitura do `ficha-dnd5e.pdf` quando o arquivo é aberto direto do disco). No GitHub Pages funciona sem configurar nada. Para testar no computador, rode `python -m http.server` na pasta do projeto e abra `http://localhost:8000`.

## Login com Supabase

O site funciona sem login, salvando no navegador. Para ativar as contas:

1. Crie uma conta em [supabase.com](https://supabase.com) e um projeto novo (região: South America, São Paulo).
2. No projeto, abra **SQL Editor**, cole o conteúdo de `supabase-setup.sql` e clique em **Run**. (Quem já tinha rodado a versão antiga só precisa rodar `supabase-compartilhar.sql`.)
3. Em **Authentication → URL Configuration**, coloque o endereço do site em **Site URL** e também em **Redirect URLs** (mais `http://localhost:8000` para testes).
4. Em **Project Settings → API Keys**, copie o **Project URL** e a chave **publishable** (ou a **anon**, na aba de chaves legadas). Nunca use a chave *secret* / *service_role* no site.
5. No `index.html`, procure `SUPABASE_URL` e cole os dois valores.

A chave publishable pode ficar no código público: o que protege as fichas são as regras de segurança criadas pelo `supabase-setup.sql`, que deixam cada pessoa ver e alterar só as próprias fichas.

## Tecnologias

HTML, CSS e JavaScript, com [pdf-lib](https://pdf-lib.js.org/) para preencher a ficha em PDF e [Supabase](https://supabase.com) para as contas.

## Conteúdo e direitos autorais

O conteúdo de regras usado aqui vem do SRD 5.1, disponibilizado pela Wizards of the Coast sob a licença Creative Commons Attribution 4.0 (CC-BY-4.0). Os textos de resumo são escritos pelo autor.

Este projeto não é afiliado à Wizards of the Coast. Dungeons & Dragons é marca registrada da Wizards of the Coast LLC.

## Autor

Artur ([@arturcsantos1610](https://github.com/arturcsantos1610))

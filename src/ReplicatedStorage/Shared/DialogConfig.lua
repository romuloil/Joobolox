-- DialogConfig (ModuleScript)
-- Caminho: ReplicatedStorage > Shared > DialogConfig
-- Todas as falas dos NPCs e do tutorial. Para mudar um texto, mude só aqui.

local DialogConfig = {}

-- Primeira vez no jogo
DialogConfig.Welcome = {
	"Olá! Eu sou o Seu Bento. Seja muito bem-vindo a Little Little Kinder!",
	"Aqui você escolhe uma profissão, ganha dinheiro, cuida da sua casa e faz amigos.",
	"Você ganhou uma bicicleta! Toque no botão Bicicleta (ou aperte B) quando quiser pedalar.",
	"Quer que eu te mostre a cidade rapidinho?",
}

-- Quando o jogador conversa com o Seu Bento depois
DialogConfig.GuideTalk = {
	"Olá de novo! Quer rever a cidade ou saber dos empregos?",
}

-- Quando o jogador pergunta sobre empregos
DialogConfig.JobsInfo = {
	"O quadro de empregos fica aqui na praça, do outro lado do ponto onde você nasce. É só chegar perto e escolher!",
	"Tem vaga de Pizzaiolo na La Paulistana, Atendente no Minas Market e Entregador na Sherlex.",
	"Para trabalhar como taxista, vá à sede amarela da LXR Táxis. O plantão policial começa na delegacia ou na prisão.",
	"Cada profissão tem seu uniforme. Retire o seu no local de trabalho; táxi e viatura também saem da garagem da profissão.",
	"Cada pedido concluído paga na hora. Para largar o emprego, toque em Sair na faixa laranja.",
}

-- Fala final (depois do tour ou de recusar o tour)
DialogConfig.Final = {
	"Se se perder, toque no botãozinho de mapa lá no alto da tela (ou aperte M) para ver onde fica cada lugar.",
	"Para ir longe rápido, use o botão Carro (ou a tecla V). Nas placas verdes das esquinas tem o nome de cada rua.",
	"Quer ganhar dinheiro? O quadro de empregos fica aqui na praça, pertinho de mim.",
}

-- Tour: primeiro a vista do alto, depois cada estabelecimento (pelo nome da placa)
DialogConfig.TourIntro = "Este é o nosso bairro! Tudo começa aqui na rotatória da praça."
DialogConfig.TourStops = {
	{ place = "La Paulistana", text = "La Paulistana: a melhor pizza da cidade. Aqui você poderá trabalhar como pizzaiolo." },
	{ place = "Minas Market", text = "Minas Market: a mercearia do bairro. Precisa de gente para repor as prateleiras!" },
	{ place = "Sherlex", text = "Sherlex: a empresa de entregas. Com a sua bicicleta você já consegue entregar pacotes." },
	{ place = "Duto Pet Shop", text = "Duto Pet Shop: aqui a gente dá banho e cuida dos bichinhos da cidade." },
}

return DialogConfig

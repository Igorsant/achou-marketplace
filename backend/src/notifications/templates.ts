import { Role } from '@prisma/client';
import { EventoPublicado } from '../outbox/eventos';
import { Email } from './email-mock.service';

/** Monta a mensagem de cada evento. Evento sem template nao notifica ninguem. */
export function montarEmail(evento: EventoPublicado): Email | null {
  switch (evento.type) {
    case 'usuario.cadastrado': {
      const { email, name, role } = evento.payload;
      const proximoPasso = role === Role.LOJISTA
        ? 'Cadastre seu primeiro produto no painel do lojista.'
        : 'Explore a vitrine e encontre o que procura.';
      return {
        para: email,
        assunto: 'Bem-vindo(a) ao Achou!',
        corpo: `Ola, ${name}! Sua conta foi criada. ${proximoPasso}`,
      };
    }
    default:
      return null;
  }
}

import { Module } from '@nestjs/common';
import { FilaModule } from '../fila/fila.module';
import { OutboxRelayService } from './outbox-relay.service';

@Module({
  imports: [FilaModule],
  providers: [OutboxRelayService],
})
export class OutboxModule {}

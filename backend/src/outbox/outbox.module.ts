import { Module } from '@nestjs/common';
import { QueueModule } from '../queue/queue.module';
import { OutboxRelayService } from './outbox-relay.service';

@Module({
  imports: [QueueModule],
  providers: [OutboxRelayService],
})
export class OutboxModule {}

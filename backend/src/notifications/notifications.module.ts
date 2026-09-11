import { Module } from '@nestjs/common';
import { QueueModule } from '../queue/queue.module';
import { NotificationsProcessor } from './notifications.processor';
import { EmailMockService } from './email-mock.service';

@Module({
  imports: [QueueModule],
  providers: [NotificationsProcessor, EmailMockService],
})
export class NotificationsModule {}

import { Module } from '@nestjs/common';
import { FilaModule } from '../fila/fila.module';
import { NotificationsProcessor } from './notifications.processor';
import { EmailMockService } from './email-mock.service';

@Module({
  imports: [FilaModule],
  providers: [NotificationsProcessor, EmailMockService],
})
export class NotificationsModule {}

from django.conf import settings
from django.contrib.auth.models import User
from django.db import models


class Mailbox(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='mailbox')
    address = models.EmailField(unique=True)
    imap_folder = models.CharField(max_length=255, default='INBOX')
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.address


class Message(models.Model):
    mailbox = models.ForeignKey(Mailbox, on_delete=models.CASCADE, related_name='messages')
    sender = models.EmailField()
    recipients = models.TextField(help_text='Comma separated list of recipients')
    subject = models.CharField(max_length=255, blank=True)
    body = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    folder = models.CharField(max_length=32, default='INBOX')
    is_read = models.BooleanField(default=False)
    has_attachments = models.BooleanField(default=False)

    class Meta:
        ordering = ['-created_at']

    def recipient_list(self):
        return [r.strip() for r in self.recipients.split(',') if r.strip()]

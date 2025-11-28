from django.contrib import admin
from .models import Mailbox, Message


@admin.register(Mailbox)
class MailboxAdmin(admin.ModelAdmin):
    list_display = ('address', 'user', 'created_at')
    search_fields = ('address', 'user__username')


@admin.register(Message)
class MessageAdmin(admin.ModelAdmin):
    list_display = ('subject', 'sender', 'folder', 'created_at')
    list_filter = ('folder', 'created_at')
    search_fields = ('subject', 'sender', 'recipients')

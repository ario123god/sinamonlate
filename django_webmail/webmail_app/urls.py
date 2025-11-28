from django.contrib import admin
from django.urls import path
from django.views.generic import RedirectView

from .views import (
    CustomLoginView,
    CustomLogoutView,
    RegisterView,
    api_create_mailbox,
    api_mailboxes,
    api_messages,
    compose,
    inbox,
)

urlpatterns = [
    path('admin/', admin.site.urls),
    path('accounts/login/', CustomLoginView.as_view(), name='login'),
    path('accounts/logout/', CustomLogoutView.as_view(), name='logout'),
    path('accounts/register/', RegisterView.as_view(), name='register'),
    path('inbox/', inbox, name='inbox'),
    path('compose/', compose, name='compose'),
    path('api/mailboxes/', api_mailboxes, name='api_mailboxes'),
    path('api/messages/', api_messages, name='api_messages'),
    path('api/mailboxes/create/', api_create_mailbox, name='api_create_mailbox'),
    path('', RedirectView.as_view(pattern_name='inbox', permanent=False)),
]

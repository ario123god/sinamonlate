import os
import smtplib
from email.message import EmailMessage
from django.contrib import messages
from django.contrib.auth import login
from django.contrib.auth.decorators import login_required
from django.contrib.auth.views import LoginView, LogoutView
from django.http import JsonResponse, HttpResponseRedirect
from django.shortcuts import get_object_or_404, redirect, render
from django.urls import reverse_lazy
from django.views.decorators.csrf import csrf_exempt
from django.views.generic import CreateView

from .forms import RegisterForm, MessageForm
from .models import Mailbox, Message


class RegisterView(CreateView):
    template_name = 'register.html'
    form_class = RegisterForm
    success_url = reverse_lazy('inbox')

    def form_valid(self, form):
        response = super().form_valid(form)
        mailbox, _created = Mailbox.objects.get_or_create(
            user=self.object,
            defaults={'address': f"{self.object.username}@webiime.ir"},
        )
        login(self.request, self.object)
        messages.success(self.request, 'Account and mailbox created.')
        return response


class CustomLoginView(LoginView):
    template_name = 'login.html'


class CustomLogoutView(LogoutView):
    next_page = reverse_lazy('login')


@login_required
def inbox(request):
    mailbox = get_object_or_404(Mailbox, user=request.user)
    messages_qs = mailbox.messages.filter(folder='INBOX')
    return render(request, 'inbox.html', {'messages': messages_qs, 'mailbox': mailbox})


@login_required
def compose(request):
    mailbox = get_object_or_404(Mailbox, user=request.user)
    if request.method == 'POST':
        form = MessageForm(request.POST, request.FILES)
        if form.is_valid():
            msg = Message.objects.create(
                mailbox=mailbox,
                sender=mailbox.address,
                recipients=form.cleaned_data['to'],
                subject=form.cleaned_data.get('subject', ''),
                body=form.cleaned_data.get('body', ''),
                folder='Sent',
                has_attachments=bool(request.FILES.getlist('attachments')),
            )
            _send_smtp(mailbox.address, form.cleaned_data['to'], msg.subject, msg.body, request.FILES.getlist('attachments'))
            messages.success(request, 'Message sent.')
            return redirect('inbox')
    else:
        form = MessageForm()
    return render(request, 'compose.html', {'form': form, 'mailbox': mailbox})


@login_required
def api_mailboxes(request):
    data = list(Mailbox.objects.all().values('id', 'address', 'user__username', 'created_at'))
    return JsonResponse({'mailboxes': data})


@login_required
def api_messages(request):
    mailbox = get_object_or_404(Mailbox, user=request.user)
    data = list(mailbox.messages.values('id', 'subject', 'sender', 'recipients', 'folder', 'created_at', 'is_read'))
    return JsonResponse({'messages': data})


@login_required
@csrf_exempt
def api_create_mailbox(request):
    if request.method != 'POST':
        return JsonResponse({'detail': 'POST required'}, status=405)
    username = request.POST.get('username')
    email = f"{username}@webiime.ir"
    if Mailbox.objects.filter(address=email).exists():
        return JsonResponse({'detail': 'Mailbox already exists'}, status=400)
    user = None
    try:
        user = type(request.user).objects.create_user(username=username, email=email, password=request.POST.get('password', os.urandom(8).hex()))
    except Exception as exc:  # pylint: disable=broad-except
        return JsonResponse({'detail': str(exc)}, status=400)
    mailbox = Mailbox.objects.create(user=user, address=email)
    return JsonResponse({'id': mailbox.id, 'address': mailbox.address})


def _send_smtp(sender, to_addresses, subject, body, attachments):
    smtp_host = os.getenv('SMTP_HOST', 'mail.webiime.ir')
    smtp_port = int(os.getenv('SMTP_PORT', '587'))
    smtp_user = os.getenv('SMTP_USER', sender)
    smtp_password = os.getenv('SMTP_PASSWORD', '')

    msg = EmailMessage()
    msg['From'] = sender
    msg['To'] = to_addresses
    msg['Subject'] = subject
    msg.set_content(body)
    for attachment in attachments or []:
        content = attachment.read()
        msg.add_attachment(content, maintype='application', subtype='octet-stream', filename=attachment.name)

    with smtplib.SMTP(smtp_host, smtp_port) as server:
        server.starttls()
        if smtp_user:
            server.login(smtp_user, smtp_password)
        server.send_message(msg)

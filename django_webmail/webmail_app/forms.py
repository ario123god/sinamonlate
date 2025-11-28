from django import forms
from django.contrib.auth.forms import UserCreationForm
from django.contrib.auth.models import User


class RegisterForm(UserCreationForm):
    email = forms.EmailField(required=True)

    class Meta:
        model = User
        fields = ('username', 'email', 'password1', 'password2')


class MessageForm(forms.Form):
    to = forms.CharField(label='To')
    subject = forms.CharField(required=False)
    body = forms.CharField(widget=forms.Textarea, required=False)
    attachments = forms.FileField(widget=forms.ClearableFileInput(attrs={'multiple': True}), required=False)

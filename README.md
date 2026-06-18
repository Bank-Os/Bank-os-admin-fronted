# BankOS Admin Frontend

Dashboard web administrativo para BankOS.

## Ejecutar

```powershell
C:\Users\monte\Downloads\flutter_windows_3.44.1-stable\flutter\bin\flutter.bat run -d chrome
```

## Build web

```powershell
C:\Users\monte\Downloads\flutter_windows_3.44.1-stable\flutter\bin\flutter.bat build web
```

## API

Consume la API publicada:

`https://bankos.bytecore.tech`

## Acceso administrativo

El panel usa el login maestro de la API:

`POST /api/v1/SuperAuth/login-master`

Las cuentas tipo `admin@banco-alfa.com` son administradores de un tenant especifico. Para entrar al dashboard principal se necesita una cuenta superadmin registrada en `SuperAuth`.

## Nota de CORS

Si se ejecuta en Flutter web local y el navegador bloquea llamadas a `https://bankos.bytecore.tech`, el ajuste debe hacerse en el backend para permitir `OPTIONS` y devolver `Access-Control-Allow-Origin` para localhost. El frontend ya apunta a la API publicada.

active trigger

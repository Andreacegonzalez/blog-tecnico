---
title: "Post-mortem: caída del servicio de checkout tras una migración de base de datos"
date: 2026-07-03
author: Andrea Cecilia González
---

# Post-mortem: caída del servicio de checkout tras una migración de base de datos

## Contexto

Trabajo en el equipo backend de una plataforma de e-commerce mediana. Somos un equipo
remoto de seis personas que trabaja con metodologías ágiles y despliegues continuos:
cada Pull Request que pasa CI y revisión se integra a `main` y se despliega automáticamente
varias veces por semana.

El servicio afectado fue el **API de checkout**, responsable de procesar carritos, calcular
totales y confirmar pagos. Es una pieza crítica: cualquier interrupción impacta directamente
en ventas.

## Problema

Durante un despliegue de rutina, se incluyó una migración de base de datos que agregaba
una columna `discount_code` a la tabla `orders`, junto con un índice para acelerar búsquedas.
La migración se ejecutó contra la base de producción sin haberse probado antes contra un
volumen de datos comparable al real.

La creación del índice bloqueó la tabla `orders` durante varios minutos. Como el checkout
depende de escrituras constantes en esa tabla, las solicitudes empezaron a acumularse y
finalmente el servicio quedó no disponible.

**Impacto:**
- 47 minutos de interrupción total del checkout.
- Pedidos abandonados durante ese período.
- Alertas automáticas activadas y escalado al equipo de guardia.

## Acciones

### Respuesta inmediata
1. El equipo de guardia detectó las alertas de latencia y error rate en menos de 3 minutos.
2. Se identificó la migración como causa probable revisando el historial de despliegues recientes.
3. Se revirtió el despliegue y se canceló la migración en curso, restaurando el servicio.

### Post-mortem constructivo

Siguiendo la plantilla del curso, documentamos el incidente enfocándonos en causas y
aprendizajes, no en responsables:

- **Línea de tiempo:** desde el inicio del despliegue hasta la resolución, minuto a minuto,
  reconstruida con logs de despliegue y métricas de monitoreo.
- **Evidencia recopilada:** logs de la base de datos, dashboards de latencia, alertas
  disparadas y el diff exacto de la migración.
- **Causas raíz:**
  - No existía un paso obligatorio de "dry run" de migraciones contra un dataset de tamaño
    similar al de producción.
  - La migración no usó una estrategia de creación de índice sin bloqueo (`CREATE INDEX
    CONCURRENTLY` en PostgreSQL).
  - No había una feature flag ni un plan de rollback específico para cambios de esquema.
- **Impacto cuantificado:** 47 minutos de caída, ventana estimada de pedidos perdidos.
- **Acciones correctivas:**
  - Se agregó un checklist obligatorio en la plantilla de PR para migraciones de base de
    datos, incluyendo pruebas de carga previas.
  - Se estandarizó el uso de creación de índices sin bloqueo.
  - Se documentó un runbook de rollback para cambios de esquema.

### Revisión de código con feedback radicalmente sincero

Al armar el Pull Request con las correcciones, aplicamos el modelo de Radical Candor:
comentarios directos sobre el riesgo técnico, pero cuidando a la persona autora del cambio
original. Ejemplo de comentario real usado en la revisión:

> "Esta migración puede bloquear la tabla en producción por el volumen de `orders`. ¿Qué te
> parece si la cambiamos a `CREATE INDEX CONCURRENTLY` y agregamos un paso de dry run
> antes del merge? Buen trabajo detectando la necesidad del índice, solo ajustemos cómo lo
> aplicamos en prod."

## Aprendizajes

- Las migraciones de esquema en tablas críticas necesitan un protocolo propio: dry run,
  estrategia sin bloqueo y plan de rollback documentado antes de mergear.
- Los post-mortems centrados en causas (no en culpas) permitieron que el autor original de
  la migración participara activamente en la solución, en lugar de ponerse a la defensiva.
- Documentar el incidente como un *issue* en GitHub, vinculado a los PRs de la corrección,
  centralizó el conocimiento y quedó accesible para todo el equipo.
- La comunicación asincrónica clara (issue + PRs bien documentados) evitó que el
  aprendizaje se perdiera en un canal de chat.

## Control de versiones: evidencia del trabajo

- **Issue del post-mortem:** `Post-mortem: Caída de checkout - 2026-07-01`
  → enlace: https://github.com/Andreacegonzalez/blog-tecnico/issues/1
- **PR con la corrección de la migración** (índice sin bloqueo):
  → enlace: https://github.com/Andreacegonzalez/blog-tecnico/pull/2
- **Commits relevantes:**
  - `Add post-mortem for checkout service outage`
  - `fix: usar CREATE INDEX CONCURRENTLY para evitar bloqueos en orders`

## Reflexión sobre feedback radicalmente sincero

Aplicar Radical Candor en este proceso significó equilibrar dos cosas al mismo tiempo:
**cuidado personal** y **desafío directo**. Fue tentador, al escribir el post-mortem, señalar
"quién" había escrito la migración riesgosa. En cambio, el documento se enfocó en el
proceso que faltó (no había dry run obligatorio) y no en la persona.

En la revisión de código, en lugar de decir "esta migración está mal", el comentario explicó
el riesgo técnico concreto, propuso una alternativa específica y reconoció el mérito de la
solución original. Esto mantuvo la seguridad psicológica del equipo: la persona autora
participó en la corrección sin sentirse señalada, y el resultado fue un checklist que ahora
protege a todo el equipo de este mismo error a futuro.

La lección más grande: la sinceridad radical no es suavizar el mensaje, es ser específico y
honesto sobre el problema técnico mientras se cuida activamente a la persona que lo recibe.

# Fase 22 — Experiencia de usuario y accesibilidad

## Cambios implementados

- Estados de carga con `role="status"`, `aria-live` y `aria-busy`.
- Mensaje recuperable cuando un módulo falla, con acción **Intentar de nuevo**.
- Botones pendientes con bloqueo, indicador visual y atributos ARIA.
- Toasts anunciados como estado o alerta según su severidad.
- Navegación principal etiquetada y ruta activa con `aria-current="page"`.
- Foco trasladado al contenido principal después de navegar.
- Modales con foco inicial, ciclo de tabulación, cierre con Escape y devolución del foco al control de origen.
- Áreas táctiles mínimas de 44 px.
- Mejoras responsive para barra superior, filtros, tarjetas, tablas, formularios y modales móviles.
- Compatibilidad con áreas seguras de dispositivos móviles.
- Soporte para `prefers-reduced-motion` y `prefers-contrast`.

## Alcance

Esta fase mejora la infraestructura visual y de interacción disponible en la copia de trabajo actual. No sustituye la integración funcional pendiente de las fases 2 a 15.

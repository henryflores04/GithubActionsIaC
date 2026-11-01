// Handler de la funcion hello.
// No usa dependencias externas a proposito: el paquete se comprime tal cual y
// no hace falta empaquetar node_modules ni construir en Docker.

export const handler = async (event) => {
  // API Gateway HTTP API (payload 2.0) entrega los claims del JWT ya
  // validados en event.requestContext.authorizer.jwt.claims.
  const jwt = event.requestContext?.authorizer?.jwt;

  const claims = jwt?.claims ?? null;

  const respuesta = {
    message: "Hola desde Lambda detras de API Gateway con autorizacion Cognito",
    environment: process.env.ENVIRONMENT ?? "desconocido",
    labPrefix: process.env.LAB_PREFIX ?? "desconocido",
    requestId: event.requestContext?.requestId ?? null,
    routeKey: event.routeKey ?? null,
    authenticated: Boolean(claims),
    // Solo se exponen los claims necesarios para la demostracion.
    subject: claims?.sub ?? null,
    email: claims?.email ?? null,
    tokenUse: claims?.token_use ?? null,
    issuedAt: claims?.iat ?? null,
    expiresAt: claims?.exp ?? null,
  };

  console.log("Invocacion:", JSON.stringify(respuesta));

  return {
    statusCode: 200,
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(respuesta),
  };
};

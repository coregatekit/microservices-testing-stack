import { yoga } from "@elysiajs/graphql-yoga";
import { Elysia } from "elysia";

new Elysia()
  .use(
    yoga({
      typeDefs: `
            type Query {
                health: String
            }
        `,
      resolvers: {
        Query: { health: () => "OK" },
      },
    }),
  )
  .listen(4000);

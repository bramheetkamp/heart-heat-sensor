import { FastifyPluginAsync } from 'fastify';

const wellknownRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.get('/apple-app-site-association', async (_request, reply) => {
    const teamId = process.env.APPLE_TEAM_ID ?? 'XXXXXXXXXX';
    const bundleId = process.env.APPLE_BUNDLE_ID ?? 'com.heartrate.app';
    const appId = `${teamId}.${bundleId}`;

    const aasa = {
      applinks: {
        details: [
          {
            appIDs: [appId],
            components: [
              { '/': '/dashboard', comment: 'Dashboard' },
              { '/': '/history/*', comment: 'History views' },
              { '/': '/warnings/*', comment: 'Warning detail' },
              { '/': '/pair', comment: 'Device pairing' },
              { '/': '/settings', comment: 'Settings' },
            ],
          },
        ],
      },
      webcredentials: {
        apps: [appId],
      },
    };

    return reply
      .header('Content-Type', 'application/json')
      .send(aasa);
  });
};

export default wellknownRoutes;

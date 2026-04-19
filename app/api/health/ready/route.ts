import prisma from '@/lib/prisma';

export async function GET() {
  try {
    await prisma.$queryRaw`SELECT 1`;
    return Response.json({ status: 'ok' });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'unknown error';
    return Response.json({ status: 'unavailable', error: message }, { status: 503 });
  }
}

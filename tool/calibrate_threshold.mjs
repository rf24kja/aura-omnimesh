// similarityThreshold calibration for RingMatcher (ROADMAP Phase 2).
// TRUE pairs = realistic offer<->need ads that SHOULD match; negatives =
// every cross-language/cross-topic combination. Embeddings from the same
// quantized MiniLM the app bundles (device parity proven to 6 decimals).
import { pipeline } from '@xenova/transformers';

const EN_PAIRS = [
  ['dart programming lessons for beginners', 'help learning flutter and dart development'],
  ['electric scooter to borrow in march', 'to borrow a scooter for a month'],
  ['weekly delivery of fresh vegetables', 'fresh groceries delivered to my door'],
  ['math tutoring for high school students', 'looking for a math tutor for my kid'],
  ['fixing leaking taps and pipes', 'need a plumber for a dripping faucet'],
  ['babysitting on weekday evenings', 'looking for a babysitter two nights a week'],
  ['guitar lessons for complete beginners', 'want to learn to play the guitar'],
  ['home cooked dinners twice a week', 'need someone to cook healthy meals'],
  ['dog walking every morning', 'need someone to walk my labrador daily'],
  ['english conversation practice sessions', 'practice spoken english with a native'],
  ['bicycle repair and maintenance', 'my bike needs new brakes and a tune up'],
  ['logo and brand identity design', 'need a designer for my startup logo'],
  ['help moving furniture this weekend', 'need two strong people to move a sofa'],
  ['translation from german to english', 'translate my documents from german'],
  ['haircuts at your home', 'looking for a mobile hairdresser'],
  ['tax return preparation for freelancers', 'help filing my self employed taxes'],
  ['yoga classes in the park', 'beginner yoga sessions outdoors'],
  ['car ride to the airport on friday', 'need a lift to the airport'],
  ['apartment deep cleaning service', 'need my flat thoroughly cleaned'],
  ['photography for small events', 'photographer needed for a birthday party'],
  ['power drill and tools to lend', 'borrow a drill for shelf mounting'],
  ['garden weeding and lawn mowing', 'need help maintaining my backyard'],
  ['laptop repair and upgrades', 'my notebook is slow and needs fixing'],
  ['sewing and clothes alteration', 'need trousers hemmed and jacket fitted'],
  ['spanish lessons over coffee', 'want to learn conversational spanish'],
];

const RU_PAIRS = [
  ['уроки программирования на dart для начинающих', 'помочь разобраться с флаттером и дартом'],
  ['отдам детскую коляску в хорошем состоянии', 'нужна коляска для новорожденного'],
  ['помогу с математикой школьнику', 'ищу репетитора по математике для сына'],
  ['ремонт протекающих кранов и труб', 'нужен сантехник кран капает'],
  ['выгул собак по утрам', 'нужен человек выгуливать лабрадора'],
  ['уроки игры на гитаре с нуля', 'хочу научиться играть на гитаре'],
  ['домашние обеды дважды в неделю', 'нужен человек готовить полезную еду'],
  ['починю велосипед и настрою тормоза', 'велосипеду нужны новые тормоза'],
  ['дизайн логотипа и фирменного стиля', 'нужен дизайнер для логотипа стартапа'],
  ['помогу перевезти мебель в выходные', 'нужны двое сильных перенести диван'],
  ['стрижка на дому', 'ищу парикмахера с выездом на дом'],
  ['занятия йогой в парке', 'йога для начинающих на свежем воздухе'],
  ['подвезу до аэропорта в пятницу', 'нужно доехать до аэропорта'],
  ['генеральная уборка квартиры', 'нужно тщательно убрать квартиру'],
  ['дам дрель и инструменты на время', 'одолжить дрель повесить полки'],
];

const embed = await pipeline('feature-extraction', 'Xenova/all-MiniLM-L6-v2', { quantized: true });
const vec = async (t) => Array.from((await embed(t, { pooling: 'mean', normalize: true })).data);
const cos = (a, b) => a.reduce((s, x, i) => s + x * b[i], 0); // both normalized

async function evaluate(pairs, label) {
  const offers = await Promise.all(pairs.map((p) => vec(p[0])));
  const needs = await Promise.all(pairs.map((p) => vec(p[1])));
  const truePos = pairs.map((_, i) => cos(offers[i], needs[i]));
  const negatives = [];
  for (let i = 0; i < pairs.length; i++) {
    for (let j = 0; j < pairs.length; j++) {
      if (i !== j) negatives.push(cos(offers[i], needs[j]));
    }
  }
  truePos.sort((a, b) => a - b);
  negatives.sort((a, b) => a - b);
  const q = (arr, p) => arr[Math.min(arr.length - 1, Math.floor(p * arr.length))];
  const stats = (arr) => ({
    min: arr[0].toFixed(3),
    p10: q(arr, 0.10).toFixed(3),
    mean: (arr.reduce((s, x) => s + x, 0) / arr.length).toFixed(3),
    p95: q(arr, 0.95).toFixed(3),
    max: arr[arr.length - 1].toFixed(3),
  });
  console.log(`\n=== ${label} (${pairs.length} true pairs, ${negatives.length} negatives)`);
  console.log('TRUE pairs :', JSON.stringify(stats(truePos)));
  console.log('NEGATIVES  :', JSON.stringify(stats(negatives)));
  for (const th of [0.40, 0.45, 0.50, 0.55]) {
    const recall = truePos.filter((x) => x >= th).length / truePos.length;
    const falseRate = negatives.filter((x) => x >= th).length / negatives.length;
    console.log(`th=${th.toFixed(2)}  recall=${(recall * 100).toFixed(0)}%  false-accept=${(falseRate * 100).toFixed(1)}%`);
  }
  const misses = pairs.filter((_, i) => cos(offers[i], needs[i]) < 0.45);
  if (misses.length) {
    console.log('missed at 0.45:', misses.map((p) => p[0]).join(' | '));
  }
}

await evaluate(EN_PAIRS, 'ENGLISH');
await evaluate(RU_PAIRS, 'RUSSIAN');

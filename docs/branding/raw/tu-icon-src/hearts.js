// Зрачки Ту заменяются чёрными сердечками, как на прежней иконке приложения.
const _eyes = blobEyes;
blobEyes = function (look, o) {
  let s = _eyes(look, o);
  s = s.replace(/<ellipse[^>]*fill="#2a2d30"[^>]*rotate\([^>]*\/>/g, '').replace(/<circle[^>]*r="1.25" fill="#fff"\/>/g, '');
  const d = 'M0,1 C-0.55,0.62 -1.05,0.2 -1.05,-0.32 C-1.05,-0.8 -0.62,-1.02 -0.3,-0.98 C-0.13,-0.95 -0.02,-0.82 0,-0.62 C0.02,-0.82 0.13,-0.95 0.3,-0.98 C0.62,-1.02 1.05,-0.8 1.05,-0.32 C1.05,0.2 0.55,0.62 0,1 Z';
  for (const [x, y, k, r] of window.HEARTS) s += `<path transform="translate(${x} ${y}) rotate(${r}) scale(${k})" fill="${INK}" d="${d}"/>`;
  return s;
};
// Без рта, как на прежней иконке.
const _cheeks = blobCheeks;
blobCheeks = function (look, o) { return _cheeks({ ...look, mouth: false }, o); };

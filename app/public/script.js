
const btn = document.getElementById('themeToggle');
btn?.addEventListener('click', () => {
  const r = document.documentElement;
  const light = r.classList.toggle('light');
  localStorage.setItem('theme', light ? 'light' : 'dark');
});


(() => {
  const pref = localStorage.getItem('theme');
  if (pref === 'light') document.documentElement.classList.add('light');
})();

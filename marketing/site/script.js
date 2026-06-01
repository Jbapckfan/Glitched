const form = document.querySelector('[data-form="stub"]');
const note = document.querySelector('#form-note');

if (form && note) {
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    note.textContent = 'Email capture is a launch stub. Connect a real provider before publishing.';
  });
}

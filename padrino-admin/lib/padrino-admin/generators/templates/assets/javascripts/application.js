// Padrino Admin, on top of Bootstrap 5. No other dependencies.
(() => {
  'use strict';

  // Ask before destructive submits: <form data-confirm="Are you sure?">
  document.addEventListener('submit', (event) => {
    const message = event.target.getAttribute('data-confirm');
    if (message && !window.confirm(message)) event.preventDefault();
  });

  document.addEventListener('DOMContentLoaded', () => {
    // Close good news after a few seconds, leave errors and warnings up.
    document.querySelectorAll('.alert-success, .alert-info').forEach((alert) => {
      setTimeout(() => bootstrap.Alert.getOrCreateInstance(alert).close(), 4000);
    });

    // Focus the first field with an error.
    const invalid = document.querySelector('.is-invalid');
    if (invalid) invalid.focus();

    const list = document.getElementById('list');
    if (!list) return;

    const all = list.querySelector('.list-select-all');
    const boxes = Array.from(list.querySelectorAll('.list-selectable-checkbox'));
    const bulk = document.querySelector('.list-bulk');

    const refresh = () => {
      const checked = boxes.filter((box) => box.checked);
      boxes.forEach((box) => box.closest('tr').classList.toggle('table-active', box.checked));
      all.checked = boxes.length > 0 && checked.length === boxes.length;
      all.indeterminate = checked.length > 0 && !all.checked;
      bulk.hidden = checked.length === 0;
      bulk.querySelector('[data-delete-many-ids]').value = checked.map((box) => box.value).join(',');
      bulk.querySelector('.list-bulk-count').textContent = checked.length;
    };

    all.addEventListener('change', () => {
      boxes.forEach((box) => { box.checked = all.checked; });
      refresh();
    });
    list.addEventListener('change', refresh);

    // A click anywhere on a row toggles it, except on its links and buttons.
    list.addEventListener('click', (event) => {
      const row = event.target.closest('.list-row');
      if (!row || event.target.closest('a, button, input, label, form')) return;
      const box = row.querySelector('.list-selectable-checkbox');
      box.checked = !box.checked;
      refresh();
    });

    refresh();
  });
})();

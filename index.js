document.addEventListener('DOMContentLoaded', () => {
  // Intersection Observer for animations
  const observerOptions = {
    threshold: 0.1
  };

  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('active');
        observer.unobserve(entry.target);
      }
    });
  }, observerOptions);

  document.querySelectorAll('[data-aos]').forEach(el => {
    observer.observe(el);
  });

  // Mobile Menu Toggle
  const menuToggle = document.getElementById('mobile-menu');
  const navList = document.querySelector('.nav-links');

  if (menuToggle) {
    menuToggle.addEventListener('click', () => {
      navList.classList.toggle('active');
      menuToggle.classList.toggle('active');
    });
  }

  // Smooth scroll logic
  const navLinks = document.querySelectorAll('.nav-links a');
  navLinks.forEach(link => {
    link.addEventListener('click', (e) => {
      // Close mobile menu on click
      if (navList.classList.contains('active')) {
        navList.classList.remove('active');
        menuToggle.classList.remove('active');
      }

      const targetId = link.getAttribute('href');
      if (targetId.startsWith('#')) {
        e.preventDefault();
        const targetElement = document.querySelector(targetId);
        if (targetElement) {
          window.scrollTo({
            top: targetElement.offsetTop - 80,
            behavior: 'smooth'
          });
        }
      }
    });
  });

  // Form handling (placeholder)
  const form = document.querySelector('#nfcForm');
  if (form) {
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      const email = form.querySelector('#email').value;
      const phone = form.querySelector('#phone').value;
      alert(`Благодарим ви! Ще се свържем с вас на ${email} или ${phone} възможно най-скоро.`);
      form.reset();
    });
  }
});

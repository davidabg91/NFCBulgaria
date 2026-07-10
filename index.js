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

  // Form handling (Web3Forms Integration)
  const form = document.querySelector('#nfcForm');
  if (form) {
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      
      const submitBtn = form.querySelector('button[type="submit"]');
      const originalBtnText = submitBtn.textContent;
      
      // Prevent double submissions
      submitBtn.disabled = true;
      submitBtn.textContent = 'Изпраща се...';
      
      // Remove any existing error message
      const existingError = form.querySelector('.form-error-msg');
      if (existingError) {
        existingError.remove();
      }
      
      const name = form.querySelector('#name').value;
      const email = form.querySelector('#email').value;
      const phone = form.querySelector('#phone').value;
      const service = form.querySelector('#service').value;
      const msg = form.querySelector('#msg').value;
      
      const formData = {
        access_key: '5baff5af-db3e-4088-9352-1381b4a700ec',
        name: name,
        email: email,
        phone: phone,
        service: service,
        message: msg,
        subject: `Ново запитване от NFC Bulgaria (${name})`,
        from_name: 'NFC Bulgaria'
      };
      
      try {
        const response = await fetch('https://api.web3forms.com/submit', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json'
          },
          body: JSON.stringify(formData)
        });
        
        const json = await response.json();
        
        if (response.status === 200 && json.success) {
          // Success: replace form with a beautiful confirmation message
          form.innerHTML = `
            <div class="success-message" style="text-align: center; padding: 3rem 1.5rem; opacity: 0; transform: translateY(10px); transition: all 0.5s ease;">
              <div style="font-size: 4.5rem; color: var(--primary); margin-bottom: 1.5rem; line-height: 1;">✓</div>
              <h3 style="font-family: var(--font-heading); font-size: 1.8rem; margin-bottom: 1rem; color: var(--text);">Благодарим Ви!</h3>
              <p style="color: var(--text-muted); font-size: 1.1rem; line-height: 1.6; max-width: 500px; margin: 0 auto 2rem;">
                Вашето запитване е изпратено успешно.<br>
                Ще се свържем с Вас на <strong>${email}</strong> или <strong>${phone}</strong> възможно най-скоро.
              </p>
            </div>
          `;
          
          // Trigger the fade-in and slide-up animation
          setTimeout(() => {
            const successDiv = form.querySelector('.success-message');
            if (successDiv) {
              successDiv.style.opacity = '1';
              successDiv.style.transform = 'translateY(0)';
            }
          }, 50);
        } else {
          // API error
          throw new Error(json.message || 'Възникна грешка при изпращането.');
        }
      } catch (error) {
        console.error(error);
        
        // Show error message to user
        const errorDiv = document.createElement('div');
        errorDiv.className = 'form-error-msg';
        errorDiv.style.color = '#ff6b6b';
        errorDiv.style.marginTop = '1rem';
        errorDiv.style.textAlign = 'center';
        errorDiv.style.fontSize = '0.95rem';
        errorDiv.style.fontFamily = 'var(--font-mono)';
        errorDiv.textContent = `Грешка: ${error.message}. Моля, опитайте отново или се обадете директно по телефона.`;
        
        form.appendChild(errorDiv);
        
        // Restore button state
        submitBtn.disabled = false;
        submitBtn.textContent = originalBtnText;
      }
    });
  }

  // Cookie Consent logic
  const consentBanner = document.getElementById('cookieConsentBanner');
  const acceptBtn = document.getElementById('btnAcceptCookies');
  const declineBtn = document.getElementById('btnDeclineCookies');
  
  if (consentBanner && acceptBtn && declineBtn) {
    const consent = localStorage.getItem('cookieConsent');
    
    // Show the banner if consent hasn't been set yet
    if (!consent) {
      setTimeout(() => {
        consentBanner.classList.add('show');
      }, 1000); // Small delay for better UX
    }
    
    acceptBtn.addEventListener('click', () => {
      localStorage.setItem('cookieConsent', 'accepted');
      // Enable GA
      window['ga-disable-G-YC72W34LWM'] = false;
      if (typeof gtag === 'function') {
        gtag('config', 'G-YC72W34LWM');
      }
      // Hide banner
      consentBanner.classList.remove('show');
    });
    
    declineBtn.addEventListener('click', () => {
      localStorage.setItem('cookieConsent', 'declined');
      // Explicitly keep GA disabled
      window['ga-disable-G-YC72W34LWM'] = true;
      // Hide banner
      consentBanner.classList.remove('show');
    });
  }
});

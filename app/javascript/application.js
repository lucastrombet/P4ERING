// app/javascript/application.js
import "@hotwired/turbo-rails"
import "controllers"
import * as bootstrap from 'bootstrap'

// Add ripple effect to buttons
document.addEventListener('DOMContentLoaded', () => {
  // Ripple effect
  const buttons = document.querySelectorAll('.btn')
  buttons.forEach(btn => {
    btn.classList.add('ripple')
  })
  
  // Smooth scroll
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
      e.preventDefault()
      const target = document.querySelector(this.getAttribute('href'))
      if (target) {
        target.scrollIntoView({ behavior: 'smooth' })
      }
    })
  })
  
  // Add loading spinner on form submit
  const forms = document.querySelectorAll('form')
  forms.forEach(form => {
    form.addEventListener('submit', () => {
      const submitBtn = form.querySelector('input[type="submit"], button[type="submit"]')
      if (submitBtn && !submitBtn.disabled) {
        submitBtn.disabled = true
        submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin me-2"></i>Processing...'
      }
    })
  })
})

// Add tooltips
const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'))
tooltipTriggerList.map(function (tooltipTriggerEl) {
  return new bootstrap.Tooltip(tooltipTriggerEl)
})

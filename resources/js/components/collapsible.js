import { slideUp, slideDown } from '../services/animations.ts';
import { Component } from './component';

export class Collapsible extends Component {

    setup() {
        this.container = this.$el;
        this.trigger = this.$refs.trigger;
        this.content = this.$refs.content;

        if (this.trigger) {
            this.trigger.addEventListener('click', this.toggle.bind(this));
            this.openIfContainsError();
        }

        // Initialize nested collapsibles
        this.container.querySelectorAll('[component="collapsible"]').forEach((nestedEl, index) => {
            if (nestedEl !== this.container) {
                new Collapsible(nestedEl);
            }
        });
        

        // Set initial state based on 'open' class
        if (this.container.classList.contains('open')) {
            this.open(true); // Pass true to skip animation on initial load
        } else {
            this.close(true);
        }
    }

    open(skipAnimation = false) {
        this.container.classList.add('open');
        this.trigger.setAttribute('aria-expanded', 'true');
        this.content.classList.remove('hidden');
        if (!skipAnimation) {
            slideDown(this.content, 300);
        }
    }

    close(skipAnimation = false) {
        this.container.classList.remove('open');
        this.trigger.setAttribute('aria-expanded', 'false');
        if (!skipAnimation) {
            slideUp(this.content, 300).then(() => {
                this.content.classList.add('hidden');
            });
        } else {
            this.content.classList.add('hidden');
        }
    }    

    toggle() {
        if (this.container.classList.contains('open')) {
            this.close();
        } else {
            this.open();
        }
    }

    openIfContainsError() {
        const error = this.content.querySelector('.text-neg.text-small');
        if (error) {
            this.open();
        }
    }

}

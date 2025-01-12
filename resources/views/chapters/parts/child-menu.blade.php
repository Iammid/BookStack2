<div component="collapsible" class="chapter-child-menu">
    @if($bookChild->pages && $bookChild->pages->count() > 0)
        <button type="button"
                refs="collapsible@toggle"
                aria-expanded="{{ $isOpen ? 'true' : 'false' }}"
                class="text-muted chapter-contents-toggle @if($isOpen) open @endif">
            @icon('caret-right') {{ trans_choice('entities.x_pages', $bookChild->pages->count()) }}
        </button>
        <ul refs="collapsible@content"
            class="chapter-contents-list sub-menu inset-list @if($isOpen) open @endif"
            role="menu">
            @foreach($bookChild->pages as $childPage)
                <li class="list-item-page {{ $childPage->isA('page') && $childPage->draft ? 'draft' : '' }}" role="presentation">
                    @include('entities.list-item-basic', ['entity' => $childPage, 'classes' => ($current->matches($childPage)? 'selected' : '') ])
                </li>
            @endforeach
        </ul>
    @endif
</div>

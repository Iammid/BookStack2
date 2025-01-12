<nav class="breadcrumbs text-center" aria-label="{{ trans('common.breadcrumb') }}">
    <?php $breadcrumbCount = 0; ?>

    {{-- Show top level books or shelves item --}}
    @if (count($crumbs) > 0)
        @if ($crumbs[0] instanceof \BookStack\Entities\Models\Bookshelf)
            <a href="{{ url('/shelves') }}" class="text-bookshelf icon-list-item outline-hover">
                <span>@icon('bookshelf')</span>
                <span>{{ trans('entities.shelves') }}</span>
            </a>
            <?php $breadcrumbCount++; ?>
        @elseif ($crumbs[0] instanceof \BookStack\Entities\Models\Book)
            <a href="{{ url('/books') }}" class="text-book icon-list-item outline-hover">
                <span>@icon('books')</span>
                <span>{{ trans('entities.books') }}</span>
            </a>
            <?php $breadcrumbCount++; ?>
        @endif
    @endif

    @foreach($crumbs as $key => $crumb)
        <?php $isEntity = ($crumb instanceof \BookStack\Entities\Models\Entity); ?>

        @if (is_null($crumb))
            <?php continue; ?>
        @endif

        @if ($breadcrumbCount !== 0 && $isEntity)
            <div class="separator">@icon('chevron-right')</div>
        @endif

        @if (is_string($crumb))
            <a href="{{ url($key) }}">
                {{ $crumb }}
            </a>
        @elseif (is_array($crumb))
            <a href="{{ url($key) }}" class="icon-list-item outline-hover">
                @if (isset($crumb['icon']))
                    <span>@icon($crumb['icon'])</span>
                @endif
                <span>{{ $crumb['text'] }}</span>
            </a>
        @elseif($isEntity && userCan('view', $crumb))
            <a href="{{ $crumb->getUrl() }}" class="text-{{ $crumb->getType() }} icon-list-item outline-hover">
                <span>@icon($crumb->getType())</span>
                <span>
                    {{ $crumb->getShortName() }}
                </span>
            </a>
        @endif
        <?php $breadcrumbCount++; ?>
    @endforeach
</nav>

/** Shapes follow directory rows while the remote catalog is pending. */
export function DirectorySkeleton() {
  return <div className="directory-skeleton" role="status" aria-label="Loading integration directory">
    <span className="sr-only">Loading integration directory…</span>
    <div className="animate-pulse motion-reduce:animate-none" aria-hidden="true">
      <div className="directory-skeleton-heading directory-skeleton-shape" />
      <div className="service-directory-list">
        {[0, 1, 2, 3].map(row => <div className="service-directory-row directory-skeleton-row" key={row}>
          <div className="directory-skeleton-logo directory-skeleton-shape" />
          <div className="service-directory-name">
            <div className="directory-skeleton-name directory-skeleton-shape" />
            <div className="directory-skeleton-detail directory-skeleton-shape" />
          </div>
          <div className="directory-skeleton-action directory-skeleton-shape" />
        </div>)}
      </div>
    </div>
  </div>;
}

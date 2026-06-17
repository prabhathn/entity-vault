import { useState } from 'react';

export default function DemoButton({ label, onClick }: { label: string; onClick: () => Promise<void> }) {
  const [loading, setLoading] = useState(false);

  const handleClick = async () => {
    setLoading(true);
    try {
      await onClick();
    } finally {
      setLoading(false);
    }
  };

  return (
    <button className="demo-btn" onClick={handleClick} disabled={loading}>
      {loading ? 'Loading...' : label}
    </button>
  );
}

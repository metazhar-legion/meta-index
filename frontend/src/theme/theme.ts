import { createTheme, alpha } from '@mui/material/styles';

// Define a modern color palette for a financial platform
const primaryColor = '#2563EB'; // Bright blue
const secondaryColor = '#10B981'; // Green for positive values
const errorColor = '#EF4444'; // Red for negative values
const warningColor = '#F59E0B'; // Amber for warnings
const infoColor = '#3B82F6'; // Blue for info
const successColor = '#10B981'; // Green for success
const backgroundColor = '#0F172A'; // Dark blue background
const paperColor = '#1E293B'; // Slightly lighter blue for cards
const chartColors = ['#3B82F6', '#10B981', '#F59E0B', '#EF4444', '#8B5CF6', '#EC4899'];

const theme = createTheme({
  palette: {
    mode: 'dark',
    primary: {
      main: primaryColor,
      light: alpha(primaryColor, 0.8),
      dark: alpha(primaryColor, 0.9),
    },
    secondary: {
      main: secondaryColor,
    },
    error: {
      main: errorColor,
    },
    warning: {
      main: warningColor,
    },
    info: {
      main: infoColor,
    },
    success: {
      main: successColor,
    },
    background: {
      default: backgroundColor,
      paper: paperColor,
    },
    text: {
      primary: '#F8FAFC',
      secondary: '#94A3B8',
    },
    divider: alpha('#94A3B8', 0.12),
  },
  typography: {
    fontFamily: [
      'Inter',
      '-apple-system',
      'BlinkMacSystemFont',
      '"Segoe UI"',
      'Roboto',
      '"Helvetica Neue"',
      'Arial',
      'sans-serif',
    ].join(','),
    h4: {
      fontWeight: 700,
      letterSpacing: '-0.01em',
    },
    h5: {
      fontWeight: 600,
      letterSpacing: '-0.01em',
    },
    h6: {
      fontWeight: 600,
      letterSpacing: '-0.01em',
    },
    subtitle1: {
      fontWeight: 500,
    },
    body1: {
      fontSize: '0.95rem',
    },
    body2: {
      fontSize: '0.875rem',
    },
  },
  shape: {
    borderRadius: 12,
  },
  components: {
    MuiCssBaseline: {
      styleOverrides: {
        body: {
          scrollbarWidth: 'thin',
          '&::-webkit-scrollbar': {
            width: '8px',
            height: '8px',
          },
          '&::-webkit-scrollbar-track': {
            background: alpha('#94A3B8', 0.05),
          },
          '&::-webkit-scrollbar-thumb': {
            background: alpha('#94A3B8', 0.2),
            borderRadius: '4px',
          },
          '&::-webkit-scrollbar-thumb:hover': {
            background: alpha('#94A3B8', 0.3),
          },
        },
      },
    },
    MuiButton: {
      styleOverrides: {
        root: {
          borderRadius: 8,
          textTransform: 'none',
          fontWeight: 600,
          boxShadow: 'none',
          '&:hover': {
            boxShadow: '0 4px 12px 0 rgba(0,0,0,0.2)',
          },
        },
        containedPrimary: {
          '&:disabled': {
            backgroundColor: alpha(primaryColor, 0.5),
            color: alpha('#F8FAFC', 0.6),
          },
        },
      },
    },
    MuiCard: {
      styleOverrides: {
        root: {
          borderRadius: 16,
          boxShadow: '0 4px 20px 0 rgba(0,0,0,0.15)',
          backdropFilter: 'blur(20px)',
          background: `linear-gradient(145deg, ${alpha(paperColor, 0.95)} 0%, ${alpha(paperColor, 0.98)} 100%)`,
          border: `1px solid ${alpha('#94A3B8', 0.08)}`,
          transition: 'transform 0.2s ease-in-out, box-shadow 0.2s ease-in-out',
          '&:hover': {
            boxShadow: '0 8px 30px 0 rgba(0,0,0,0.2)',
          },
        },
      },
    },
    MuiCardContent: {
      styleOverrides: {
        root: {
          padding: '24px',
          '&:last-child': {
            paddingBottom: '24px',
          },
        },
      },
    },
    MuiTableCell: {
      styleOverrides: {
        root: {
          borderBottom: `1px solid ${alpha('#94A3B8', 0.08)}`,
        },
        head: {
          fontWeight: 600,
          color: '#94A3B8',
        },
      },
    },
    MuiTableRow: {
      styleOverrides: {
        root: {
          '&:hover': {
            backgroundColor: alpha('#94A3B8', 0.04),
          },
        },
      },
    },
    MuiDivider: {
      styleOverrides: {
        root: {
          borderColor: alpha('#94A3B8', 0.08),
        },
      },
    },
    MuiTab: {
      styleOverrides: {
        root: {
          textTransform: 'none',
          fontWeight: 600,
          minWidth: 'auto',
          padding: '12px 16px',
        },
      },
    },
    MuiChip: {
      styleOverrides: {
        root: {
          fontWeight: 500,
        },
      },
    },
  },
});

// Export chart colors for use in components
export { chartColors };
export default theme;

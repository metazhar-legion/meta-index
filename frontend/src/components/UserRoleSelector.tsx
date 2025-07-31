import React from 'react';
import { Box, ToggleButton, ToggleButtonGroup, Typography } from '@mui/material';
import { useWeb3, UserRole } from '../contexts/Web3Context';
import PersonIcon from '@mui/icons-material/Person';
import GroupsIcon from '@mui/icons-material/Groups';
import AccountBalanceIcon from '@mui/icons-material/AccountBalance';
import ShowChartIcon from '@mui/icons-material/ShowChart';

const UserRoleSelector: React.FC = () => {
  const { userRole, setUserRole, isActive } = useWeb3();

  const handleRoleChange = (
    event: React.MouseEvent<HTMLElement>,
    newRole: UserRole | null
  ) => {
    if (newRole !== null) {
      setUserRole(newRole);
    }
  };

  if (!isActive) {
    return null;
  }

  return (
    <Box sx={{ mt: 2, mb: 2 }}>
      <Typography variant="subtitle2" sx={{ mb: 1 }}>
        Select Your Role:
      </Typography>
      <ToggleButtonGroup
        value={userRole}
        exclusive
        onChange={handleRoleChange}
        aria-label="user role"
        size="small"
      >
        <ToggleButton value={UserRole.INVESTOR} aria-label="investor">
          <PersonIcon sx={{ mr: 1 }} />
          Investor
        </ToggleButton>
        <ToggleButton value={UserRole.DAO_MEMBER} aria-label="dao member">
          <GroupsIcon sx={{ mr: 1 }} />
          DAO Member
        </ToggleButton>
        <ToggleButton value={UserRole.PORTFOLIO_MANAGER} aria-label="portfolio manager">
          <AccountBalanceIcon sx={{ mr: 1 }} />
          Portfolio Manager
        </ToggleButton>
        <ToggleButton value={UserRole.COMPOSABLE_RWA_USER} aria-label="composable rwa user">
          <ShowChartIcon sx={{ mr: 1 }} />
          Composable RWA
        </ToggleButton>
      </ToggleButtonGroup>
    </Box>
  );
};

export default UserRoleSelector;
